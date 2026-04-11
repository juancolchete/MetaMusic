#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input.lrc> <output.mp4>"
    exit 1
fi

LRC_FILE="$1"
OUT_MP4="$2"

BASENAME=$(basename -- "$LRC_FILE")
FILENAME="${BASENAME%.*}"

# Check for audio source
AUDIO_FILE="audio/${FILENAME}.mp3"

ASS_FILE="${LRC_FILE%.*}.ass"
DURATION_FILE=$(mktemp)

echo "Processing: $LRC_FILE..."

# 1. Parse LRC and generate ASS file with Karaoke tags
awk '
BEGIN {
    print "[Script Info]"
    print "Title: Procedural Tunnel Karaoke"
    print "ScriptType: v4.00+"
    print "PlayDepth: 0"
    print ""
    print "[V4+ Styles]"
    print "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding"
    # Primary: Yellow (sung word); Secondary: White (upcoming words)
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
            # Cap the highlight sweeping duration to 5 seconds max
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

# 2. Render Video
if [ -f "$AUDIO_FILE" ]; then
    echo "Audio file found: $AUDIO_FILE. Generating dynamic spectrogram background..."
    
    ffmpeg -y \
        -i "$AUDIO_FILE" \
        -filter_complex "[0:a]showspectrum=s=1920x1080:mode=combined:color=fire:slide=scroll:scale=cbrt[bg]; [bg]ass='${ASS_FILE}'[v]" \
        -map "[v]" -map 0:a \
        -c:v libx264 \
        -preset ultrafast \
        -crf 28 \
        -pix_fmt yuv420p \
        -c:a aac \
        "$OUT_MP4"
else
    echo "No audio found. Procedurally generating hypnotic Mandelbrot background using code..."
    
    HASH=$(sha256sum "$LRC_FILE" | awk '{print substr($1, 1, 6)}')
    HEX_X=$(echo "${HASH}" | awk '{print substr($1, 1, 3)}')
    HEX_Y=$(echo "${HASH}" | awk '{print substr($1, 4, 3)}')
    DEC_X=$((0x${HEX_X}))
    DEC_Y=$((0x${HEX_Y}))
    
    START_X=$(awk "BEGIN {print ($DEC_X / 4095.0 * 4.0) - 2.0}")
    START_Y=$(awk "BEGIN {print ($DEC_Y / 4095.0 * 4.0) - 2.0}")
    
    echo "Lyrics hash: #$HASH -> Seed Coords: ($START_X, $START_Y)"

    ffmpeg -y \
        -f lavfi -i "mandelbrot=s=1920x1080:d=${DURATION}:maxiter=150:start_x=${START_X}:start_y=${START_Y}" \
        -vf "ass='${ASS_FILE}'" \
        -c:v libx264 \
        -preset ultrafast \
        -crf 28 \
        -pix_fmt yuv420p \
        -an \
        "$OUT_MP4"
fi

echo "Success! Video saved to $OUT_MP4"
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
            # Cap long lines
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

# 2. Render Video
if [ -f "$AUDIO_FILE" ]; then
    echo "Audio file found: $AUDIO_FILE. Generating dynamic spectrogram background..."
    # Specialist Note: Spectrogram remains the highest priority visual fallback
    ffmpeg -y \
        -i "$AUDIO_FILE" \
        -filter_complex "[0:a]showspectrum=s=1920x1080:mode=combined:color=fire:slide=scroll:scale=cbrt[bg]; [bg]ass='${ASS_FILE}'[v]" \
        -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -c:a aac "$OUT_MP4" > /dev/null 2>&1
else
    echo "No audio found. Procedurally generating hypnotic Mandelbrot Hall of Mirrors background using code..."
    
    # Generate unique start coordinates from lyrics content hash (Deterministic Randomness)
    # sha256 -> HEX(6) -> Normalize to mathematical range [-2.0, 2.0]
    HASH=$(sha256sum "$LRC_FILE" | awk '{print substr($1, 1, 6)}')
    HEX_X=$(echo "${HASH}" | awk '{print substr($1, 1, 3)}')
    HEX_Y=$(echo "${HASH}" | awk '{print substr($1, 4, 3)}')
    DEC_X=$((0x${HEX_X}))
    DEC_Y=$((0x${HEX_Y}))
    
    # Normalized coords [-2.0, 2.0]
    START_X=$(awk "BEGIN {print ($DEC_X / 4095.0 * 4.0) - 2.0}")
    START_Y=$(awk "BEGIN {print ($DEC_Y / 4095.0 * 4.0) - 2.0}")
    
    echo "Lyrics hash: #$HASH -> Seed Coords: ($START_X, $START_Y)"

    # Procedural Rendering Pipeline:
    # 1. source: mandelbrot (generated in memory)
    # 2. filter_complex:
    #    - zoompan: Animates the fractal depth over time ('zoom+0.001') to simulate infinite forward motion.
    #    - ass: Burns the timed lyrics over the Mandelbrot tunnel.
    ffmpeg -y \
        -f lavfi -i mandelbrot=s=1920x1080:d=${DURATION}:maxiter=200:start_x=${START_X}:start_y=${START_Y} \
        -filter_complex \
        "[0:v]zoompan=z='zoom+0.001':x='x':y='y':s=1920x1080[depth]; \
         [depth]ass='${ASS_FILE}'[v]" \
        -map "[v]" \
        -c:v libx264 \
        -pix_fmt yuv420p \
        -an \
        "$OUT_MP4" > /dev/null 2>&1
fi

echo "Success! Video saved to $OUT_MP4"
