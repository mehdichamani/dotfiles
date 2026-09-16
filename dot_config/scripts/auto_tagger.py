#!/usr/bin/env python3
"""
Auto-Tagger: Intelligent Music Metadata, High-Res Cover Art & Lyrics Tagger
Supports MP3, FLAC, M4A/MP4, OGG, and Opus formats.
Powered by Apple iTunes API, LRCLib, and Mutagen.
"""

import os
import re
import sys
import argparse
import urllib.parse
import urllib.request
import json
from pathlib import Path
from typing import Optional, Dict, Any, List

# --- Terminal Styling ---
class Colors:
    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RESET = "\033[0m"

    @classmethod
    def disable(cls):
        cls.HEADER = ""
        cls.BLUE = ""
        cls.CYAN = ""
        cls.GREEN = ""
        cls.YELLOW = ""
        cls.RED = ""
        cls.BOLD = ""
        cls.DIM = ""
        cls.RESET = ""

# Disable colors if not running in a TTY or on unsupported Windows terminals
if not sys.stdout.isatty() or (os.name == 'nt' and 'ANSICON' not in os.environ and 'WT_SESSION' not in os.environ):
    if os.name == 'nt':
        try:
            os.system('')  # Enable ANSI in Windows 10/11 CMD/PowerShell
        except Exception:
            Colors.disable()

# --- Mutagen Imports ---
try:
    import mutagen
    from mutagen.id3 import ID3, TIT2, TPE1, TALB, TDRC, TRCK, TCON, APIC, USLT, TXXX, error as ID3Error
    from mutagen.mp3 import MP3
    from mutagen.flac import FLAC, Picture
    from mutagen.mp4 import MP4, MP4Cover, MP4FreeForm
    from mutagen.oggvorbis import OggVorbis
    from mutagen.oggopus import OggOpus
except ImportError:
    print(f"{Colors.RED}Error: 'mutagen' library is required.{Colors.RESET}")
    print("Install it with: pip install mutagen or through your system package manager.")
    sys.exit(1)


SUPPORTED_EXTENSIONS = {".mp3", ".flac", ".m4a", ".mp4", ".ogg", ".opus"}


def clean_filename_for_search(filename: str) -> str:
    """Clean common junk, track numbers, and noise from filenames to optimize search query."""
    name = Path(filename).stem
    
    # Strip leading track numbers like "01 - ", "01. ", "01 "
    name = re.sub(r"^\s*\d{1,3}[\s.\-_]+", "", name)
    
    # Remove bracketed extras often found in downloads
    name = re.sub(r"\[.*?\]", "", name)
    name = re.sub(r"\(Official\s*(Music\s*)?(Video|Audio|HD|4K|Visualizer|Lyric\s*Video)?.*?\)", "", name, flags=re.IGNORECASE)
    name = re.sub(r"\(Audio\)", "", name, flags=re.IGNORECASE)
    name = re.sub(r"\(Lyric(s)?\)", "", name, flags=re.IGNORECASE)
    name = re.sub(r"\(Music Video\)", "", name, flags=re.IGNORECASE)
    name = re.sub(r"\(Video\)", "", name, flags=re.IGNORECASE)
    name = re.sub(r"\(Remix\)", "Remix", name, flags=re.IGNORECASE)
    
    # Remove bitrate/format artifacts
    name = re.sub(r"\b(320kbps|256kbps|128kbps|flac|mp3|m4a|kbps)\b", "", name, flags=re.IGNORECASE)
    
    # Replace special separators with space
    name = re.sub(r"[\-_~]+", " ", name)
    # Remove quotes / backticks
    name = re.sub(r"['\"`’‘]", "", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name


def sanitize_filename_part(part: str) -> str:
    """Sanitize string to be safely used as part of a cross-platform filename."""
    # Replace illegal filesystem chars across Windows/Linux/macOS/FAT32: / \ : * ? " < > |
    cleaned = re.sub(r'[\\/*?:"<>|]', "", part)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned


def rename_audio_file(file_path: Path, artist: str, title: str, dry_run: bool = False) -> Path:
    """Rename audio file (and matching sidecar .lrc) to 'Artist - Title.ext'."""
    clean_artist = sanitize_filename_part(artist)
    clean_title = sanitize_filename_part(title)
    
    if not clean_artist or not clean_title or clean_artist.lower() == "unknown" or clean_title.lower() == "unknown":
        print(f"  {Colors.YELLOW}[!] Skipping rename: Missing clean Artist/Title metadata.{Colors.RESET}")
        return file_path
        
    ext = file_path.suffix.lower()
    new_name = f"{clean_artist} - {clean_title}{ext}"
    target_path = file_path.parent / new_name

    if target_path.name == file_path.name:
        print(f"  {Colors.DIM}📄 Filename already normalized:{Colors.RESET} {new_name}")
        return file_path

    if target_path.exists() and target_path != file_path:
        print(f"  {Colors.YELLOW}[!] Cannot rename: Target file '{new_name}' already exists.{Colors.RESET}")
        return file_path

    if dry_run:
        print(f"  {Colors.YELLOW}[Dry-Run]{Colors.RESET} Would rename: {Colors.DIM}'{file_path.name}'{Colors.RESET} -> {Colors.GREEN}'{new_name}'{Colors.RESET}")
        return file_path

    try:
        # Rename sidecar lrc if present
        old_lrc = file_path.parent / f"{file_path.stem}.lrc"
        new_lrc = file_path.parent / f"{clean_artist} - {clean_title}.lrc"
        if old_lrc.exists() and not new_lrc.exists():
            old_lrc.rename(new_lrc)
            print(f"  {Colors.DIM}Renamed sidecar lyrics to:{Colors.RESET} {new_lrc.name}")

        file_path.rename(target_path)
        print(f"  {Colors.GREEN}✓ Renamed file to:{Colors.RESET} {Colors.BOLD}{new_name}{Colors.RESET}")
        return target_path
    except Exception as e:
        print(f"  {Colors.RED}✗ Failed to rename file: {e}{Colors.RESET}")
        return file_path


TAG_KEY = "AUTOTAGGED"
TAG_VAL = "1"


def is_already_tagged(file_path: Path) -> bool:
    """Check if the audio file was already processed and tagged by this utility."""
    ext = file_path.suffix.lower()
    try:
        if ext == ".mp3":
            try:
                tags = ID3(file_path)
                for tag in tags.getall("TXXX"):
                    if tag.desc.upper() == TAG_KEY and TAG_VAL in tag.text:
                        return True
            except ID3Error:
                return False
        elif ext == ".flac":
            audio = FLAC(file_path)
            if TAG_KEY in audio and TAG_VAL in audio[TAG_KEY]:
                return True
        elif ext in {".m4a", ".mp4"}:
            audio = MP4(file_path)
            key = f"----:com.apple.iTunes:{TAG_KEY}"
            if key in audio:
                vals = audio[key]
                if any(TAG_VAL.encode() in v or v == TAG_VAL for v in vals):
                    return True
        elif ext in {".ogg", ".opus"}:
            audio = OggOpus(file_path) if ext == ".opus" else OggVorbis(file_path)
            if TAG_KEY in audio and TAG_VAL in audio[TAG_KEY]:
                return True
    except Exception:
        pass
    return False


def generate_deep_queries(filename: str) -> List[str]:
    """Generate aggressive candidate queries for tricky/failed tracks."""
    stem = Path(filename).stem
    queries: List[str] = []

    # 1. Clean brackets, qualities, and common noisy words
    s = re.sub(r"\[.*?\]", "", stem)
    s = re.sub(r"\(.*?\)", "", s)
    s = re.sub(r"\b(320kbps|256kbps|128kbps|flac|mp3|m4a|kbps)\b", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\b(OFFICIAL\s*(MUSIC\s*)?(VIDEO|AUDIO|HD|4K|VISUALIZER|LYRIC\s*VIDEO)?|MUSIC\s*VIDEO|AUDIO|COVER)\b", "", s, flags=re.IGNORECASE)

    # 2. Split by Pipe/Bar (common in bilingual YouTube titles: English | Persian)
    if any(p in s for p in ["|", "｜", "丨"]):
        parts = re.split(r"[|｜丨]", s)
        for p in parts:
            p_clean = re.sub(r"[\-_~]+", " ", p).strip()
            if p_clean and len(p_clean) > 2:
                queries.append(p_clean)

    s_norm = s
    if "_" in s_norm and "-" not in s_norm:
        s_norm = s_norm.replace("_", " ")

    # 3. Split by Dash: "Artist - Title" vs "Title - Artist"
    dash_match = re.split(r"\s+-\s+|\s*-\s*", s_norm)
    if len(dash_match) == 2:
        part1, part2 = dash_match[0].strip(), dash_match[1].strip()
        queries.append(f"{part1} {part2}")
        queries.append(f"{part2} {part1}")

        # Strip secondary artists from part 1: "A & B" -> "A"
        clean_p1 = re.split(r"\s+(?:x|feat\.?|ft\.?|&)\s+", part1, flags=re.IGNORECASE)[0].strip()
        if clean_p1 != part1:
            queries.append(f"{clean_p1} {part2}")
            queries.append(f"{part2} {clean_p1}")
    elif " x " in s_norm or " feat " in s_norm:
        parts = re.split(r"\s+(?:x|feat\.?|ft\.?)\s+", s_norm, flags=re.IGNORECASE)
        if len(parts) >= 2:
            queries.append(s_norm)
            queries.append(f"{parts[0]} {parts[-1]}")

    # 4. Strip Persian/Non-Latin if bilingual to isolate clean Latin query
    latin_only = re.sub(r"[^\x00-\x7F]+", " ", s)
    latin_only = re.sub(r"[\-_~]+", " ", latin_only).strip()
    latin_only = re.sub(r"\s+", " ", latin_only)
    if len(latin_only) > 3:
        queries.append(latin_only)

    # Deduplicate while preserving order
    seen = set()
    result = []
    for q in queries:
        q_clean = re.sub(r"\s+", " ", q).strip()
        if q_clean and q_clean.lower() not in seen:
            seen.add(q_clean.lower())
            result.append(q_clean)
    return result


def fetch_metadata_from_itunes(query: str) -> Optional[Dict[str, Any]]:
    """Search Apple iTunes API for song metadata."""
    base_url = "https://itunes.apple.com/search"
    queries_to_try = [query]
    
    # Fallback search strategies
    if " - " in query:
        parts = query.split(" - ", 1)
        queries_to_try.append(f"{parts[0]} {parts[1]}")
    elif " " in query:
        words = query.split()
        if len(words) > 4:
            queries_to_try.append(" ".join(words[:4]))

    for q in queries_to_try:
        params = {
            "term": q,
            "entity": "song",
            "limit": 3
        }
        url = f"{base_url}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("resultCount", 0) > 0:
                    item = data["results"][0]
                    item["_source"] = "iTunes"
                    return item
        except Exception:
            continue
    return None


def fetch_metadata_from_deezer(query: str) -> Optional[Dict[str, Any]]:
    """Secondary search using Deezer Public API (no registration or API key required)."""
    try:
        url = f"https://api.deezer.com/search?q={urllib.parse.quote(query)}"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=7) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            items = data.get("data", [])
            if items:
                first = items[0]
                # Map Deezer object structure to unified iTunes format
                mapped = {
                    "trackName": first.get("title") or first.get("title_short"),
                    "artistName": first.get("artist", {}).get("name", "Unknown"),
                    "collectionName": first.get("album", {}).get("title", "Unknown"),
                    "primaryGenreName": "",
                    "releaseDate": "",
                    "trackNumber": 1,
                    "trackCount": 1,
                    "artworkUrl100": first.get("album", {}).get("cover_xl") or first.get("album", {}).get("cover_big") or first.get("album", {}).get("cover_medium"),
                    "_source": "Deezer"
                }
                return mapped
    except Exception:
        pass
    return None


def fetch_metadata_from_musicbrainz(query: str) -> Optional[Dict[str, Any]]:
    """Secondary search using MusicBrainz Open API (great for underground/Persian releases)."""
    try:
        url = f"https://musicbrainz.org/ws/2/recording/?query={urllib.parse.quote(query)}&fmt=json&limit=3"
        req = urllib.request.Request(url, headers={"User-Agent": "AutoTagger/1.1 ( dotfiles-auto-tagger )"})
        with urllib.request.urlopen(req, timeout=7) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            recordings = data.get("recordings", [])
            if recordings:
                rec = recordings[0]
                artist_credit = rec.get("artist-credit", [{}])[0]
                artist_name = artist_credit.get("name", "Unknown") if isinstance(artist_credit, dict) else "Unknown"
                title = rec.get("title", "Unknown")
                
                album_name = "Single"
                release_date = ""
                releases = rec.get("releases", [])
                release_id = None
                if releases:
                    first_rel = releases[0]
                    album_name = first_rel.get("title", "Single")
                    release_date = first_rel.get("date", "")
                    release_id = first_rel.get("id")

                # Look up Cover Art Archive if release_id exists
                art_url = None
                if release_id:
                    art_url = f"https://coverartarchive.org/release/{release_id}/front-500"

                mapped = {
                    "trackName": title,
                    "artistName": artist_name,
                    "collectionName": album_name,
                    "primaryGenreName": "",
                    "releaseDate": release_date,
                    "trackNumber": 1,
                    "trackCount": 1,
                    "artworkUrl100": art_url,
                    "_source": "MusicBrainz"
                }
                return mapped
    except Exception:
        pass
    return None


def fetch_metadata(query: str, deep: bool = False, filename: str = "") -> Optional[Dict[str, Any]]:
    """Unified metadata search: iTunes first, with deep queries and secondary APIs on fallback."""
    # 1. Primary iTunes attempt
    meta = fetch_metadata_from_itunes(query)
    if meta:
        return meta

    if not deep:
        return None

    # Deep Search phase: generate alternative queries
    deep_queries = generate_deep_queries(filename) if filename else []
    if query not in deep_queries:
        deep_queries.insert(0, query)

    for dq in deep_queries:
        # Retry iTunes with refined query
        meta = fetch_metadata_from_itunes(dq)
        if meta:
            return meta

        # Try Deezer
        meta = fetch_metadata_from_deezer(dq)
        if meta:
            return meta

        # Try MusicBrainz
        meta = fetch_metadata_from_musicbrainz(dq)
        if meta:
            return meta

    return None


def fetch_online_lyrics(artist: str, title: str) -> str:
    """Fetch lyrics from LRCLib API or lyrics.ovh."""
    # 1. Try lrclib.net (Rich database, supports synced and plain lyrics)
    try:
        query = f"{artist} {title}"
        url = f"https://lrclib.net/api/search?q={urllib.parse.quote(query)}"
        req = urllib.request.Request(url, headers={"User-Agent": "AutoTagger/1.0"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data and isinstance(data, list):
                lyrics = data[0].get("plainLyrics") or data[0].get("syncedLyrics")
                if lyrics and len(lyrics.strip()) > 10:
                    return lyrics.strip()
    except Exception:
        pass

    # 2. Try lyrics.ovh fallback
    try:
        url = f"https://api.lyrics.ovh/v1/{urllib.parse.quote(artist)}/{urllib.parse.quote(title)}"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            lyrics = data.get("lyrics", "").strip()
            if lyrics and len(lyrics) > 10:
                return lyrics
    except Exception:
        pass

    return ""


def download_artwork(art_url_100: str, resolution: int = 1200) -> Optional[bytes]:
    """Download cover artwork upgraded to specified resolution."""
    hi_res_url = art_url_100.replace("100x100bb", f"{resolution}x{resolution}bb")
    req = urllib.request.Request(hi_res_url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            return resp.read()
    except Exception:
        # Fallback to original URL if hi-res failed
        try:
            with urllib.request.urlopen(art_url_100, timeout=10) as resp:
                return resp.read()
        except Exception:
            return None


def tag_mp3(file_path: str, meta: dict, art_bytes: Optional[bytes], lyrics_text: str, dry_run: bool = False):
    """Embed ID3v2 tags, APIC cover art, and USLT lyrics into MP3."""
    title = meta.get("trackName", "")
    artist = meta.get("artistName", "")
    album = meta.get("collectionName", "")
    genre = meta.get("primaryGenreName", "")
    year = str(meta.get("releaseDate", ""))[:4]
    track_num = meta.get("trackNumber")
    track_count = meta.get("trackCount")
    track_str = f"{track_num}/{track_count}" if track_num and track_count else (str(track_num) if track_num else "")

    if dry_run:
        return

    try:
        tags = ID3(file_path)
    except ID3Error:
        tags = ID3()

    if title:
        tags.add(TIT2(encoding=3, text=[title]))
    if artist:
        tags.add(TPE1(encoding=3, text=[artist]))
    if album:
        tags.add(TALB(encoding=3, text=[album]))
    if year:
        tags.add(TDRC(encoding=3, text=[year]))
    if track_str:
        tags.add(TRCK(encoding=3, text=[track_str]))
    if genre:
        tags.add(TCON(encoding=3, text=[genre]))

    if art_bytes:
        tags.add(APIC(
            encoding=3,
            mime="image/jpeg",
            type=3,  # Front Cover
            desc="Front Cover",
            data=art_bytes
        ))

    if lyrics_text:
        tags.add(USLT(encoding=3, lang="eng", desc="", text=lyrics_text))

    # Add identifier tag so future runs can skip this file
    tags.add(TXXX(encoding=3, desc=TAG_KEY, text=[TAG_VAL]))

    tags.save(file_path, v2_version=3)


def tag_flac(file_path: str, meta: dict, art_bytes: Optional[bytes], lyrics_text: str, dry_run: bool = False):
    """Embed Vorbis comments and Picture block into FLAC."""
    title = meta.get("trackName", "")
    artist = meta.get("artistName", "")
    album = meta.get("collectionName", "")
    genre = meta.get("primaryGenreName", "")
    year = str(meta.get("releaseDate", ""))[:4]
    track_num = meta.get("trackNumber")
    track_count = meta.get("trackCount")

    if dry_run:
        return

    audio = FLAC(file_path)
    if title:
        audio["TITLE"] = [title]
    if artist:
        audio["ARTIST"] = [artist]
    if album:
        audio["ALBUM"] = [album]
    if year:
        audio["DATE"] = [year]
    if track_num:
        audio["TRACKNUMBER"] = [str(track_num)]
    if track_count:
        audio["TRACKTOTAL"] = [str(track_count)]
    if genre:
        audio["GENRE"] = [genre]
    if lyrics_text:
        audio["LYRICS"] = [lyrics_text]

    # Add identifier tag
    audio[TAG_KEY] = [TAG_VAL]

    if art_bytes:
        # Clear existing front covers
        audio.clear_pictures()
        pic = Picture()
        pic.type = 3  # Front cover
        pic.mime = "image/jpeg"
        pic.desc = "Front Cover"
        pic.data = art_bytes
        audio.add_picture(pic)

    audio.save()


def tag_mp4(file_path: str, meta: dict, art_bytes: Optional[bytes], lyrics_text: str, dry_run: bool = False):
    """Embed iTunes tags and cover art into M4A / MP4."""
    title = meta.get("trackName", "")
    artist = meta.get("artistName", "")
    album = meta.get("collectionName", "")
    genre = meta.get("primaryGenreName", "")
    year = str(meta.get("releaseDate", ""))[:4]
    track_num = meta.get("trackNumber")
    track_count = meta.get("trackCount")

    if dry_run:
        return

    audio = MP4(file_path)
    if title:
        audio["\xa9nam"] = [title]
    if artist:
        audio["\xa9ART"] = [artist]
    if album:
        audio["\xa9alb"] = [album]
    if year:
        audio["\xa9day"] = [year]
    if genre:
        audio["\xa9gen"] = [genre]
    if track_num:
        audio["trkn"] = [(track_num, track_count or 0)]
    if lyrics_text:
        audio["\xa9lyr"] = [lyrics_text]

    # Add identifier tag
    audio[f"----:com.apple.iTunes:{TAG_KEY}"] = [MP4FreeForm(TAG_VAL.encode("utf-8"))]

    if art_bytes:
        audio["covr"] = [MP4Cover(art_bytes, imageformat=MP4Cover.FORMAT_JPEG)]

    audio.save()


def tag_ogg_opus(file_path: str, meta: dict, lyrics_text: str, dry_run: bool = False):
    """Embed Vorbis comments into Ogg/Opus files."""
    if dry_run:
        return

    ext = Path(file_path).suffix.lower()
    audio = OggOpus(file_path) if ext == ".opus" else OggVorbis(file_path)
    
    if meta.get("trackName"):
        audio["TITLE"] = [meta["trackName"]]
    if meta.get("artistName"):
        audio["ARTIST"] = [meta["artistName"]]
    if meta.get("collectionName"):
        audio["ALBUM"] = [meta["collectionName"]]
    if meta.get("releaseDate"):
        audio["DATE"] = [str(meta["releaseDate"])[:4]]
    if meta.get("primaryGenreName"):
        audio["GENRE"] = [meta["primaryGenreName"]]
    if meta.get("trackNumber"):
        audio["TRACKNUMBER"] = [str(meta["trackNumber"])]
    if lyrics_text:
        audio["LYRICS"] = [lyrics_text]

    # Add identifier tag
    audio[TAG_KEY] = [TAG_VAL]

    audio.save()


def process_file(file_path: Path, args: argparse.Namespace, deep: bool = False) -> Optional[Path]:
    """Process a single audio file: search metadata, download art & lyrics, tag, and optionally rename."""
    print(f"\n{Colors.BOLD}🎵 Processing:{Colors.RESET} {Colors.CYAN}{file_path.name}{Colors.RESET}")

    # Check if file was already processed and tagged
    if not getattr(args, "force", False) and is_already_tagged(file_path):
        print(f"  {Colors.DIM}⏩ Skipping: Already tagged by Auto-Tagger (use --force to re-tag).{Colors.RESET}")
        return file_path

    query = args.query if args.query else clean_filename_for_search(file_path.name)
    print(f"  {Colors.DIM}🔍 Search Query:{Colors.RESET} '{query}'" + (f" {Colors.YELLOW}[Deep Mode]{Colors.RESET}" if deep else ""))

    meta = fetch_metadata(query, deep=deep, filename=file_path.name)
    if not meta:
        print(f"  {Colors.RED}✗ No online metadata match found.{Colors.RESET}")
        return None

    source = meta.get("_source", "iTunes")
    title = meta.get("trackName", "Unknown")
    artist = meta.get("artistName", "Unknown")
    album = meta.get("collectionName", "Unknown")
    genre = meta.get("primaryGenreName", "Unknown")
    year = str(meta.get("releaseDate", ""))[:4]
    track_num = meta.get("trackNumber")
    track_count = meta.get("trackCount")
    track_str = f"{track_num}/{track_count}" if track_num and track_count else (str(track_num) if track_num else "-")

    print(f"  {Colors.GREEN}✓ Match Found via {source}:{Colors.RESET}")
    print(f"    {Colors.BOLD}Title:{Colors.RESET}   {title}")
    print(f"    {Colors.BOLD}Artist:{Colors.RESET}  {artist}")
    print(f"    {Colors.BOLD}Album:{Colors.RESET}   {album} {f'({year})' if year else ''}")
    print(f"    {Colors.BOLD}Genre:{Colors.RESET}   {genre if genre else '-'} | {Colors.BOLD}Track:{Colors.RESET} {track_str}")

    # Cover Art
    art_bytes = None
    if not args.no_cover and "artworkUrl100" in meta:
        art_bytes = download_artwork(meta["artworkUrl100"], resolution=args.resolution)
        if art_bytes:
            print(f"    {Colors.BOLD}Artwork:{Colors.RESET} Downloaded ({args.resolution}x{args.resolution} px, {len(art_bytes)//1024} KB)")
        else:
            print(f"    {Colors.YELLOW}[!] Could not download cover artwork.{Colors.RESET}")

    # Lyrics Search
    lyrics_text = ""
    if not args.no_lyrics:
        base_stem = file_path.stem
        parent_dir = file_path.parent
        
        # Check local sidecar files first
        for lrc_candidate in [parent_dir / f"{base_stem}.lrc", parent_dir / f"{base_stem}.en.lrc", parent_dir / "lyrics.md"]:
            if lrc_candidate.exists():
                try:
                    with open(lrc_candidate, "r", encoding="utf-8") as lf:
                        lyrics_text = lf.read().strip()
                    print(f"    {Colors.BOLD}Lyrics:{Colors.RESET}  Found local sidecar ({lrc_candidate.name})")
                    break
                except Exception:
                    pass

        # If not found locally, fetch online
        if not lyrics_text and artist and title:
            online_lyrics = fetch_online_lyrics(artist, title)
            if online_lyrics:
                lyrics_text = online_lyrics
                line_count = len(lyrics_text.splitlines())
                print(f"    {Colors.BOLD}Lyrics:{Colors.RESET}  Fetched online ({line_count} lines)")

    # Tag according to format
    ext = file_path.suffix.lower()
    try:
        if ext == ".mp3":
            tag_mp3(str(file_path), meta, art_bytes, lyrics_text, dry_run=args.dry_run)
        elif ext == ".flac":
            tag_flac(str(file_path), meta, art_bytes, lyrics_text, dry_run=args.dry_run)
        elif ext in {".m4a", ".mp4"}:
            tag_mp4(str(file_path), meta, art_bytes, lyrics_text, dry_run=args.dry_run)
        elif ext in {".ogg", ".opus"}:
            tag_ogg_opus(str(file_path), meta, lyrics_text, dry_run=args.dry_run)
        else:
            print(f"  {Colors.RED}Unsupported format: {ext}{Colors.RESET}")
            return None

        if args.dry_run:
            print(f"  {Colors.YELLOW}[Dry-Run]{Colors.RESET} Tags simulated, no file changes saved.")
        else:
            print(f"  {Colors.GREEN}✓ Successfully tagged and embedded metadata!{Colors.RESET}")

        # Optional file renaming to "Artist - Title.ext"
        current_path = file_path
        if args.rename:
            current_path = rename_audio_file(file_path, artist, title, dry_run=args.dry_run)

        return current_path
    except Exception as e:
        print(f"  {Colors.RED}✗ Error saving tags: {e}{Colors.RESET}")
        return None


def build_parser() -> argparse.ArgumentParser:
    """Construct a clean, rich CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="autotag",
        description=f"{Colors.BOLD}{Colors.HEADER}Auto-Tagger:{Colors.RESET} Automated Music Tag, Hi-Res Artwork & Lyrics Fetcher.",
        epilog="""
Examples:
  autotag                               Tag music in current directory (recursive)
  autotag --rename                      Tag and rename files to 'Artist - Title.ext'
  autotag /path/to/music -R             Process specific directory and rename all files
  autotag song.mp3                      Tag a single audio file
  autotag song.mp3 -q "Adele Hello"     Tag using a custom search query
  autotag --dry-run                     Preview tags and renaming without modifying files
  autotag --no-lyrics --no-cover        Tag metadata only (skip lyrics and art)
  autotag --no-recursive                Scan current directory only (non-recursive)
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="Target audio file or directory to process (default: current directory '.')"
    )
    parser.add_argument(
        "-R", "--rename",
        action="store_true",
        help="Rename audio file (and sidecar .lrc) to 'Artist - Title.ext' based on tags"
    )
    parser.add_argument(
        "-n", "--dry-run",
        action="store_true",
        help="Simulate tagging and renaming without modifying files"
    )
    parser.add_argument(
        "-r", "--recursive",
        dest="recursive",
        action="store_true",
        default=True,
        help="Recursively scan subdirectories (enabled by default)"
    )
    parser.add_argument(
        "--no-recursive", "--flat",
        dest="recursive",
        action="store_false",
        help="Do not scan subdirectories recursively"
    )
    parser.add_argument(
        "-q", "--query",
        type=str,
        help="Override search query for matching (recommended for single files)"
    )
    parser.add_argument(
        "--no-cover", "--no-art",
        action="store_true",
        help="Skip searching and downloading cover art"
    )
    parser.add_argument(
        "--no-lyrics",
        action="store_true",
        help="Skip searching and embedding lyrics"
    )
    parser.add_argument(
        "-s", "--resolution",
        type=int,
        default=1200,
        help="Target artwork resolution in px (default: 1200)"
    )
    parser.add_argument(
        "--no-report",
        action="store_true",
        help="Do not generate tagger_report.txt summary file"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Force re-tagging even if files were already tagged by Auto-Tagger"
    )
    parser.add_argument(
        "--deep",
        action="store_true",
        help="Enable aggressive query fallback and secondary APIs immediately without prompting"
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    target = Path(args.path).expanduser().resolve()
    if not target.exists():
        print(f"{Colors.RED}Error: Path '{target}' does not exist.{Colors.RESET}")
        sys.exit(1)

    print(f"\n{Colors.BOLD}{Colors.HEADER}=== Auto-Tagger Music Library Utility ==={Colors.RESET}")
    print(f"Target: {Colors.CYAN}{target}{Colors.RESET}")
    if args.rename:
        print(f"Format: {Colors.GREEN}Auto-Rename enabled ('Artist - Title.ext'){Colors.RESET}")
    if args.dry_run:
        print(f"Mode:   {Colors.YELLOW}Dry-Run (Simulation){Colors.RESET}")

    if target.is_file():
        if target.suffix.lower() not in SUPPORTED_EXTENSIONS:
            print(f"{Colors.RED}Error: Unsupported file format '{target.suffix}'. Supported: {', '.join(sorted(SUPPORTED_EXTENSIONS))}{Colors.RESET}")
            sys.exit(1)

        result_path = process_file(target, args, deep=args.deep)
        success = result_path is not None
        if not args.no_report and not args.dry_run:
            report_file = target.parent / "tagger_report.txt"
            final_name = result_path.name if result_path else target.name
            with open(report_file, "a", encoding="utf-8") as rf:
                rf.write(f"[{'DONE' if success else 'NOT FOUND'}] {final_name}\n")
            print(f"\n{Colors.DIM}Report updated: {report_file}{Colors.RESET}")

    elif target.is_dir():
        files: List[Path] = []
        if args.recursive:
            for ext in SUPPORTED_EXTENSIONS:
                files.extend(target.rglob(f"*{ext}"))
        else:
            for ext in SUPPORTED_EXTENSIONS:
                files.extend(target.glob(f"*{ext}"))

        files = sorted(files)
        if not files:
            print(f"\n{Colors.YELLOW}No supported audio files found in {target}.{Colors.RESET}")
            sys.exit(0)

        print(f"Found {Colors.BOLD}{len(files)}{Colors.RESET} audio file(s). Starting tagging process...\n" + "-" * 50)
        
        tracks_done = []
        tracks_not_found = []

        # Pass 1: Standard Search (fast iTunes search)
        for f in files:
            res = process_file(f, args, deep=args.deep)
            if res:
                tracks_done.append(res)
            else:
                tracks_not_found.append(f)

        # Pass 2: Interactive Deep Search for tracks that were not found
        if tracks_not_found and not args.deep and not args.dry_run:
            print(f"\n{Colors.BOLD}{Colors.YELLOW}" + "=" * 50 + f"{Colors.RESET}")
            print(f"{Colors.YELLOW}[?] {len(tracks_not_found)} track(s) could not be matched with standard search.{Colors.RESET}")
            try:
                # Prompt user interactively
                choice = input(f"{Colors.BOLD}Would you like to run Deep Search (aggressive queries + secondary APIs) on them? [Y/n]: {Colors.RESET}").strip().lower()
            except (EOFError, KeyboardInterrupt):
                choice = "n"

            if choice in {"", "y", "yes"}:
                print(f"\n{Colors.CYAN}Starting Deep Search on {len(tracks_not_found)} file(s)...{Colors.RESET}\n" + "-" * 50)
                still_not_found = []
                for f in tracks_not_found:
                    res = process_file(f, args, deep=True)
                    if res:
                        tracks_done.append(res)
                    else:
                        still_not_found.append(f)
                tracks_not_found = still_not_found

        # Summary output
        print(f"\n{Colors.BOLD}=========================================={Colors.RESET}")
        print(f"{Colors.GREEN}Done!{Colors.RESET} Successfully processed {Colors.BOLD}{len(tracks_done)}/{len(files)}{Colors.RESET} files.")

        if not args.no_report and not args.dry_run:
            report_file = target / "tagger_report.txt"
            with open(report_file, "w", encoding="utf-8") as rf:
                rf.write("=========================================\n")
                rf.write(f" Auto-Tagger Report: {target}\n")
                rf.write(f" Total Files Processed: {len(files)}\n")
                rf.write(f" Successfully Tagged : {len(tracks_done)}\n")
                rf.write(f" Not Found / Failed  : {len(tracks_not_found)}\n")
                rf.write("=========================================\n\n")

                rf.write(f"### TRACKS NOT FOUND ({len(tracks_not_found)}):\n")
                if tracks_not_found:
                    for f in tracks_not_found:
                        rf.write(f"  [X] {f.relative_to(target) if target.is_dir() else f.name}\n")
                else:
                    rf.write("  (None! All tracks matched)\n")

                rf.write(f"\n### TRACKS DONE ({len(tracks_done)}):\n")
                if tracks_done:
                    for f in tracks_done:
                        rf.write(f"  [✓] {f.relative_to(target) if target.is_dir() else f.name}\n")
                else:
                    rf.write("  (None)\n")

            print(f"Summary report written to: {Colors.CYAN}{report_file}{Colors.RESET}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Operation cancelled by user.{Colors.RESET}")
        sys.exit(130)
