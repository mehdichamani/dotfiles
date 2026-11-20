function fix-bitchord-tags --description "Remux BitChord m4a files to fix cover art metadata and move to Musics"
    set -l src "/sdcard/Music/BitChord"
    set -l dst "/sdcard/media/Musics"

    if not test -d "$src"
        echo (set_color red)"❌ Source directory not found: $src"(set_color normal)
        return 1
    end

    mkdir -p "$dst"

    set -l files "$src"/*.m4a
    if test (count $files) -eq 0 -o ! -f "$files[1]"
        echo (set_color yellow)"⚠️ No m4a files found in $src"(set_color normal)
        return 0
    end

    set -l count 0
    for f in $files
        test -f "$f"; or continue
        set -l filename (path basename "$f")
        echo (set_color cyan)"🔄 Processing:"(set_color normal) "$filename"
        if ffmpeg -v error -y -i "$f" -c copy "$dst/$filename"
            rm "$f"
            set count (math $count + 1)
        else
            echo (set_color red)"❌ Failed to process:"(set_color normal) "$filename"
        end
    end

    echo (set_color green)"✨ Finished: $count file(s) remuxed and moved to $dst"(set_color normal)
end
