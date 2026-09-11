import os
import sys
import shutil
import subprocess
import argparse
import time
import re
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor

VERSION = "2.4"

VIDEO_EXTENSIONS = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv', '.m4v'}

# --- Configuration & Constants ---

FILTERS = {
    1: {'name': 'Crop1 (ED2)', 'filter': 'crop=900:900:850:180'},
    2: {'name': 'Crop2 (ED1)', 'filter': 'crop=900:900:450:80'},
    3: {'name': 'Light & Noise Fix', 'filter': 'hqdn3d=3:2.25:9:6,eq=brightness=0.30:contrast=1.6:saturation=1.3:gamma=1.1'},
    4: {'name': 'Strong Sharp & Noise', 'filter': 'unsharp=7:7:1.5:7:7:0.0'},
    5: {'name': 'Soft Sharp & Noise', 'filter': 'smartblur=1.5:-0.35:-3.5:0.65:0.25:2.0'},
    6: {'name': 'beta', 'filter': 'eq=brightness=0.30:contrast=1.5'}
}

# Encoder Mapping: (Type) -> { (Codec) -> (Encoder Name) }
ENCODER_MAP = {
    'cpu': {
        'h264': 'libx264',
        'hevc': 'libx265',
        'av1':  'libsvtav1', # Better performance than libaom
        'vp9':  'libvpx-vp9'
    },
    'nvidia': {
        'h264': 'h264_nvenc',
        'hevc': 'hevc_nvenc',
        'av1':  'av1_nvenc', # RTX 40 series
        'vp9':  'vp9_nvenc'  # Rare, strictly usually decoding, but keeping for mapping
    },
    'amd': {
        'h264': 'h264_amf',
        'hevc': 'hevc_amf',
        'av1':  'av1_amf',
        'vp9':  'unknown_amf' 
    },
    'intel': {
        'h264': 'h264_qsv',
        'hevc': 'hevc_qsv',
        'av1':  'av1_qsv',
        'vp9':  'vp9_qsv'
    },
    'vaapi': {
        'h264': 'h264_vaapi',
        'hevc': 'hevc_vaapi',
        'av1':  'av1_vaapi',
        'vp9':  'vp9_vaapi'
    },
    'apple': {
        'h264': 'h264_videotoolbox',
        'hevc': 'hevc_videotoolbox',
        'av1':  'unknown_vt',
        'vp9':  'unknown_vt'
    }
}

class FFmpegOptimizer:
    def __init__(self, input_dir, output_dir=None, codec='h264', encoder_type='cpu', recursive=False, dry_run=False):
        self.input_dir = Path(input_dir).resolve()
        self.output_dir = Path(output_dir).resolve() if output_dir else self.input_dir / 'output'
        self.codec = codec
        self.encoder_type = encoder_type
        self.recursive = recursive
        self.dry_run = dry_run
        
        self.ffmpeg_bin = shutil.which('ffmpeg')
        self.ffprobe_bin = shutil.which('ffprobe')
        
        if not self.ffmpeg_bin or not self.ffprobe_bin:
            raise FileNotFoundError("FFmpeg or FFprobe not found in PATH.")

        self.selected_encoder = self._resolve_encoder()

    def _detect_available_encoders(self):
        """Detects available encoders using ffmpeg -encoders."""
        try:
            result = subprocess.run([self.ffmpeg_bin, '-encoders'], capture_output=True, text=True, check=True)
            available = set()
            for line in result.stdout.splitlines():
                # Example line: V..... libx264             Convert libx264 to H.264 video
                parts = line.split()
                if len(parts) >= 2:
                    available.add(parts[1])
            return available
        except subprocess.CalledProcessError:
            return set()

    def _resolve_encoder(self):
        """Resolves the specific ffmpeg encoder string based on type and codec."""
        available_encoders = self._detect_available_encoders()
        
        # Default to CPU if type not found
        type_map = ENCODER_MAP.get(self.encoder_type, ENCODER_MAP['cpu'])
        
        # Get encoder name, fallback to CPU version if specific hw codec missing
        encoder_name = type_map.get(self.codec)
        
        if not encoder_name or 'unknown' in encoder_name or encoder_name not in available_encoders:
            print(f"⚠️  Warning: Encoder '{encoder_name}' not found or not available. Falling back to CPU.")
            return ENCODER_MAP['cpu'][self.codec]
            
        return encoder_name

    def get_video_files(self):
        if self.recursive:
            files = [f for f in self.input_dir.rglob('*') if f.suffix.lower() in VIDEO_EXTENSIONS]
        else:
            files = [f for f in self.input_dir.iterdir() if f.is_file() and f.suffix.lower() in VIDEO_EXTENSIONS]
        return sorted(files)

    def get_duration(self, file_path):
        try:
            cmd = [self.ffprobe_bin, '-v', 'error', '-show_entries', 'format=duration', 
                   '-of', 'default=noprint_wrappers=1:nokey=1', str(file_path)]
            result = subprocess.run(cmd, capture_output=True, text=True)
            return float(result.stdout.strip())
        except (ValueError, subprocess.CalledProcessError):
            return None

    def build_command(self, input_path, output_path, filter_chain, crf=None, preset=None, bitrate=None):
        cmd = [self.ffmpeg_bin, '-y', '-i', str(input_path)]
        
        # Special handling for VAAPI (often needs init arguments), 
        # but for simple "manual test" we append standard filter chain
        if filter_chain:
            cmd.extend(['-vf', filter_chain])
        
        # Encoding settings
        cmd.extend(['-c:v', self.selected_encoder])
        
        # Rate Control Logic
        if crf:
            cmd.extend(['-crf', str(crf)])
        elif bitrate:
            cmd.extend(['-b:v', bitrate])

        if preset:
            cmd.extend(['-preset', preset])
        elif 'lib' in self.selected_encoder and 'svt' not in self.selected_encoder: 
            # Standard CPU (libx264, libx265)
            if not crf: cmd.extend(['-crf', '23'])
            cmd.extend(['-preset', 'medium'])
        elif 'svtav1' in self.selected_encoder:
            # SVT AV1
            if not crf: cmd.extend(['-crf', '30'])
            if not preset: cmd.extend(['-preset', '8']) 
        elif 'vaapi' in self.selected_encoder:
             # VAAPI usually fails with CRF/CQ, often needs explicit QP or bitrate in simple CLI
             cmd.extend(['-qp', '24'])
        else: 
            # Other Hardware (NVENC, AMF, QSV, Videotoolbox)
            if not crf and not bitrate:
                if 'nvenc' in self.selected_encoder:
                    cmd.extend(['-cq', '23'])
                else:
                    cmd.extend(['-b:v', '5M'])

        cmd.extend(['-c:a', 'copy', str(output_path)])
        return cmd

    def process(self, filter_indices, crf=None, preset=None, bitrate=None, workers=1):
        print(f"\n--- Starting Optimization ---")
        print(f"Input: {self.input_dir}")
        print(f"Output: {self.output_dir}")
        print(f"Encoder: {self.selected_encoder} (Type: {self.encoder_type})")
        print(f"Codec: {self.codec}")
        print(f"Workers: {workers}")
        
        if not self.dry_run:
            self.output_dir.mkdir(parents=True, exist_ok=True)

        files = self.get_video_files()
        if not files:
            print("No video files found.")
            return

        # Prepare Filter String
        selected_filters_list = [FILTERS[i]['filter'] for i in filter_indices if i in FILTERS]
        filter_str = ','.join(selected_filters_list) if selected_filters_list else None
        
        suffix_ids = ','.join(map(str, filter_indices)) if filter_indices else "converted"
        
        if workers > 1:
            print(f"🚀 Running in parallel with {workers} workers...")
            with ProcessPoolExecutor(max_workers=workers) as executor:
                for i, file_path in enumerate(files, 1):
                    output_file = self.output_dir / f"{file_path.stem}_opt({suffix_ids}).{self.codec}"
                    duration = self.get_duration(file_path)
                    cmd = self.build_command(file_path, output_file, filter_str, crf, preset, bitrate)
                    
                    print(f"[{i}/{len(files)}] Queuing: {file_path.name}")
                    executor.submit(self._run_ffmpeg_worker, cmd, duration, file_path.name)
        else:
            for i, file_path in enumerate(files, 1):
                output_file = self.output_dir / f"{file_path.stem}_opt({suffix_ids}).{self.codec}"
                
                print(f"\n[{i}/{len(files)}] Processing: {file_path.name}")
                
                if self.dry_run:
                    print(f"  -> Would save to: {output_file}")
                    continue

                duration = self.get_duration(file_path)
                cmd = self.build_command(file_path, output_file, filter_str, crf, preset, bitrate)
                
                self._run_ffmpeg(cmd, duration)

    def _run_ffmpeg_worker(self, cmd, duration, filename):
        """Worker function for parallel processing."""
        try:
            start_time = time.time()
            process = subprocess.Popen(cmd, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True, bufsize=1)
            
            time_pattern = re.compile(r'time=([\d:.]+)')
            
            while True:
                line = process.stderr.readline()
                if not line and process.poll() is not None:
                    break
                
                if line:
                    match = time_pattern.search(line)
                    if match:
                        current_time_str = match.group(1)
                        current_seconds = self._parse_time(current_time_str)
                        
                        percent = 0
                        if duration:
                            percent = min(100, (current_seconds / duration) * 100)
                        
                        elapsed = time.time() - start_time
                        speed = current_seconds / elapsed if elapsed > 0 else 0
                        # For parallel, we just print a simple line per file
                        # print(f"\r[{filename}] Progress: {percent:5.1f}% [Speed: {speed:.1f}x]", end='', flush=True)
                        pass

            if process.returncode != 0:
                print(f"❌ Error processing {filename}")
            else:
                final_elapsed = time.time() - start_time
                print(f"✅ Done: {filename} ({final_elapsed:.1f}s)")
        except Exception as e:
            print(f"❌ Error processing {filename}: {e}")

    def _run_ffmpeg(self, cmd, total_duration):
        start_time = time.time()
        process = subprocess.Popen(cmd, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True, bufsize=1)
        
        time_pattern = re.compile(r'time=([\d:.]+)')
        
        while True:
            line = process.stderr.readline()
            if not line and process.poll() is not None:
                break
            
            if line:
                match = time_pattern.search(line)
                if match:
                    current_time_str = match.group(1)
                    current_seconds = self._parse_time(current_time_str)
                    
                    percent = 0
                    if total_duration:
                        percent = min(100, (current_seconds / total_duration) * 100)
                    
                    elapsed = time.time() - start_time
                    speed = current_seconds / elapsed if elapsed > 0 else 0
                    
                    bar_length = 30
                    filled_length = int(bar_length * percent // 100)
                    bar = '█' * filled_length + '-' * (bar_length - filled_length)
                    
                    # MODIFIED: Removed Time display, kept speed
                    print(f"\rProgress: |{bar}| {percent:5.1f}% [Speed: {speed:.1f}x]", end='', flush=True)

        print() # Newline after progress
        
        if process.returncode != 0:
            print("❌ Error during processing.")
        else:
            final_elapsed = time.time() - start_time
            print(f"✅ Done in {final_elapsed:.1f} seconds")

    def _parse_time(self, time_str):
        try:
            parts = time_str.split(':')
            if len(parts) == 3:
                return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
            elif len(parts) == 2:
                return float(parts[0]) * 60 + float(parts[1])
            return float(parts[0])
        except (ValueError, IndexError):
            return 0.0


# --- Interactive Functions ---

def list_filters():
    print("\nAvailable Filters:")
    for k, v in FILTERS.items():
        print(f"  [{k}] {v['name']}")
        print(f"       {v['filter']}")
    print("  [0] Convert Only (No Filters)")


def interactive_mode():
    print(f"\n--- FFmpeg Optimizer v{VERSION} ---")
    
    # 1. Directory (Defaulted)
    input_dir = Path.cwd()
    print(f"Directory: {input_dir} (Default)")
    
    # 2. Filters
    list_filters()
    
    sel = input("\nSelect filters (comma separated, e.g. 1,3) [Default 1,3,4]: ").strip()
    if not sel:
        indices = [1, 3, 4]
    elif sel == '0':
        indices = []
    else:
        try:
            indices = [int(x) for x in sel.split(',') if x.strip()]
        except ValueError:
            print("Invalid input. Using default.")
            indices = [1, 3, 4]

    # 3. Codec Selection
    print("\nCodec Options:")
    print("[1] H.264 (Standard)")
    print("[2] H.265/HEVC (Efficient)")
    print("[3] AV1 (Next Gen/Slow)")
    print("[4] VP9 (Web)")
    
    c_map = {'1': 'h264', '2': 'hevc', '3': 'av1', '4': 'vp9'}
    c_choice = input("Select Codec [1]: ").strip()
    codec = c_map.get(c_choice, 'h264')

    # 4. Encoder Selection
    print("\nEncoder Options (Manual Test):")
    print("[1] CPU (Default - Most Compatible)")
    print("[2] NVIDIA (NVENC)")
    print("[3] AMD (AMF)")
    print("[4] INTEL (QSV)")
    print("[5] VAAPI (Generic/Linux)")
    print("[6] Apple (VideoToolbox)")
    
    e_map = {'1': 'cpu', '2': 'nvidia', '3': 'amd', '4': 'intel', '5': 'vaapi', '6': 'apple'}
    e_choice = input("Select Encoder [1]: ").strip()
    encoder_type = e_map.get(e_choice, 'cpu')

    # 5. Granular Controls
    print("\nGranular Controls (Leave blank for default):")
    crf = input("  CRF (e.g. 23): ").strip() or None
    preset = input("  Preset (e.g. medium): ").strip() or None
    bitrate = input("  Bitrate (e.g. 5M): ").strip() or None

    # 6. Parallelism
    workers = input("\nNumber of parallel workers [Default 1]: ").strip()
    try:
        workers = int(workers) if workers else 1
    except ValueError:
        workers = 1

    # Output Directory
    output_dir = input("\nOutput directory [Default: ./output]: ").strip() or None

    # Run
    optimizer = FFmpegOptimizer(input_dir, output_dir=output_dir, codec=codec, encoder_type=encoder_type)
    optimizer.process(indices, crf=crf, preset=preset, bitrate=bitrate, workers=workers)
    print("\nDone!")

# --- Main Entry ---

def main():
    parser = argparse.ArgumentParser(description="Optimize videos with FFmpeg")
    parser.add_argument('--version', action='version', version=f'%(prog)s {VERSION}')
    parser.add_argument('--dir', type=str, help="Input directory")
    parser.add_argument('--output', '-o', type=str, help="Output directory")
    parser.add_argument('--filters', type=str, help="Comma separated filter IDs (e.g. 1,3)")
    parser.add_argument('--list-filters', action='store_true', help="List all available filters and exit")
    parser.add_argument('--encoder', type=str, default='cpu', 
                        choices=['cpu', 'nvidia', 'amd', 'intel', 'vaapi', 'apple'], 
                        help="Encoder type")
    parser.add_argument('--codec', type=str, default='h264', 
                        choices=['h264', 'hevc', 'av1', 'vp9'], 
                        help="Video codec")
    parser.add_argument('--recursive', action='store_true', help="Scan subdirectories")
    parser.add_argument('--dry-run', action='store_true', help="Don't process, just show what would happen")
    parser.add_argument('--crf', type=str, help="CRF value (e.g. 23)")
    parser.add_argument('--preset', type=str, help="Encoder preset (e.g. medium)")
    parser.add_argument('--bitrate', type=str, help="Video bitrate (e.g. 5M)")
    parser.add_argument('--workers', type=int, default=1, help="Number of parallel workers")
    
    args = parser.parse_args()

    if args.list_filters:
        list_filters()
        return

    if len(sys.argv) == 1:
        interactive_mode()
    else:
        input_dir = args.dir or os.getcwd()
        
        indices = []
        if args.filters:
            if args.filters == '0':
                indices = []
            else:
                indices = [int(x) for x in args.filters.split(',')]
        else:
            indices = [1, 3, 4]

        try:
            opt = FFmpegOptimizer(input_dir, output_dir=args.output, encoder_type=args.encoder, 
                                  codec=args.codec, recursive=args.recursive, dry_run=args.dry_run)
            opt.process(indices, crf=args.crf, preset=args.preset, bitrate=args.bitrate, workers=args.workers)
        except FileNotFoundError as e:
            print(f"Error: {e}")
            sys.exit(1)
        except Exception as e:
            print(f"Error: {e}")
            sys.exit(1)

if __name__ == '__main__':
    main()