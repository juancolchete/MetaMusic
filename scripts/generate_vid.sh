#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input.lrc> <output.mp4>"
    exit 1
fi

LRC_FILE="$1"
OUT_MP4="$2"

# Extract filename to check for matching audio
BASENAME=$(basename -- "$LRC_FILE")
FILENAME="${BASENAME%.*}"
AUDIO_FILE="audio/${FILENAME}.mp3"

ASS_FILE="${LRC_FILE%.*}.ass"
DURATION_FILE=$(mktemp)

echo "Processing: $LRC_FILE..."

# 1. Parse LRC and generate ASS file with Karaoke tags
awk '
BEGIN {
    print "[Script Info]"
    print "Title: Silent Karaoke"
    print "ScriptType: v4.00+"
    print "PlayDepth: 0"
    print ""
    print "[V4+ Styles]"
    print "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding"
    print "Style: Default,Arial,32,&H0000FFFF,&H00FFFFFF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,1,2,0,5,10,10,10,1"
    print ""
    print "[Events]"
    print "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
    count = 0
}
{
    if ($0 !~ /^\[[0-9]+:[0-9]+\.[0-9]+\]/) next;

    split($0, parts, "]");
    time_str = substr(parts[1], 2);
    text_str = substr($0, length(parts[1]) + 2);
    
    sub(/^[ \t]+/, "", text_str);
    sub(/[ \t]+$/, "", text_str);

    split(time_str, t, ":");
    min = t[1] + 0;
    sec = t[2] + 0;
    curr_total_sec = (min * 60) + sec;

    h = int(min / 60);
    m = min % 60;
    start_time = sprintf("%d:%02d:%05.2f", h, m, sec);

    if (count > 0 && prev_text != "") {
        duration_sec = curr_total_sec - prev_total_sec;
        words_count = split(prev_text, w, " ");
        if (words_count > 0) {
            highlight_duration = duration_sec;
            if (highlight_duration > 5) highlight_duration = 5;
            
            time_per_word_cs = int((highlight_duration * 100) / words_count);
            
            k_text = "";
            for (i=1; i<=words_count; i++) {
                k_text = k_text "{\\kf" time_per_word_cs "}" w[i] " ";
            }
            print "Dialogue: 0," prev_start "," start_time ",Default,,0,0,0,," k_text;
        }
    }

    prev_start = start_time;
    prev_total_sec = curr_total_sec;
    prev_text = text_str;
    last_sec = sec;
    last_min = min;
    count++;
}
END {
    if (count == 0) exit;

    end_sec = last_sec + 5;
    end_min = last_min;
    if (end_sec >= 60) {
        end_min += int(end_sec / 60);
        end_sec = end_sec % 60;
    }
    
    h = int(end_min / 60);
    m = end_min % 60;
    end_time = sprintf("%d:%02d:%05.2f", h, m, end_sec);

    if (prev_text != "") {
        words_count = split(prev_text, w, " ");
        time_per_word_cs = int((5 * 100) / words_count); 
        k_text = "";
        for (i=1; i<=words_count; i++) {
            k_text = k_text "{\\kf" time_per_word_cs "}" w[i] " ";
        }
        print "Dialogue: 0," prev_start "," end_time ",Default,,0,0,0,," k_text;
    }

    total_duration = end_min * 60 + end_sec + 3;
    print total_duration > "'"$DURATION_FILE"'";
}
' "$LRC_FILE" > "$ASS_FILE"

DURATION=$(cat "$DURATION_FILE")
rm -f "$DURATION_FILE"

if [ -z "$DURATION" ]; then
    echo "Error: Could not calculate duration."
    exit 1
fi

echo "Video duration set to: $DURATION seconds"

# 2. Render Video based on Audio presence
if [ -f "$AUDIO_FILE" ]; then
    echo "Audio file found: $AUDIO_FILE. Generating Spectrogram background..."
    
    # Generate a scrolling spectrogram and overlay ASS subtitles
    ffmpeg -y \
        -i "$AUDIO_FILE" \
        -filter_complex \
        "[0:a]showspectrum=s=1920x1080:mode=combined:color=fire:slide=scroll:scale=cbrt[bg]; \
         [bg]ass='${ASS_FILE}'[v]" \
        -map "[v]" -map 0:a \
        -c:v libx264 -pix_fmt yuv420p \
        -c:a aac \
        "$OUT_MP4" > /dev/null 2>&1
else
    # Generate a unique HEX color by hashing the lyrics file contents
    HEX_COLOR=$(sha256sum "$LRC_FILE" | awk '{print substr($1, 1, 6)}')
    echo "No audio file found. Generated unique background color based on lyrics: #$HEX_COLOR"
    
    ffmpeg -y \
        -f lavfi \
        -i "color=c=0x${HEX_COLOR}:s=1920x1080:d=${DURATION}" \
        -vf "ass='${ASS_FILE}'" \
        -c:v libx264 -pix_fmt yuv420p \
        -an \
        "$OUT_MP4" > /dev/null 2>&1
fi

echo "Success! Video saved to $OUT_MP4"
