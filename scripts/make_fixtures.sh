#!/bin/bash
# Erzeugt die Testvideos in Tests/Fixtures/Videos (einmalig, Ergebnis liegt im Repository).
#
# Die Dateien sind selbst erzeugte Testbilder mit Ton (6 Sekunden, 320×180) – keine fremden Filme.
# Sie decken alle Formate ab, die die App erkennt, dazu Kapitel, mehrere Tonspuren, eingebettete
# Untertitel, eingebettetes Cover, ein Posterbild im Ordner, externe Untertitel und kaputte Dateien.
#
#   scripts/make_fixtures.sh            (braucht ffmpeg mit libx264, libx265, libvpx, libopus, libmp3lame)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="Tests/Fixtures/Videos"
rm -rf "$OUT"
mkdir -p "$OUT/Mit Poster" "$OUT/Serien/Staffel 1" "$OUT/Kaputt"
FONT="${FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf}"
FF=(ffmpeg -hide_banner -loglevel error -y)
DUR=6

# Bildquelle mit Beschriftung (Format-Name groß in der Mitte, laufende Zeit unten)
src() { # $1 = Muster, $2 = Text
    echo "$1=size=320x180:rate=25,trim=duration=$DUR,drawtext=fontfile=$FONT:text='$2':fontsize=28:fontcolor=white:borderw=3:bordercolor=black@0.7:x=(w-tw)/2:y=(h-th)/2-10,drawtext=fontfile=$FONT:text='%{pts\\:hms}':fontsize=14:fontcolor=white:borderw=2:bordercolor=black:x=(w-tw)/2:y=h-28"
}
tone() { echo "sine=frequency=$1:sample_rate=48000:duration=$DUR"; }

# Kapitel-Datei (FFMETADATA)
META="$(mktemp)"
cat > "$META" <<'EOF'
;FFMETADATA1
title=Testfilm mit Kapiteln
[CHAPTER]
TIMEBASE=1/1000
START=0
END=3000
title=Anfang
[CHAPTER]
TIMEBASE=1/1000
START=3000
END=6000
title=Schluss
EOF

# Cover-Bild (für eingebettetes Cover und Poster im Ordner)
"${FF[@]}" -f lavfi -i "gradients=size=400x600:c0=0x1d2b64:c1=0xf8cdda:duration=1:speed=0.01,drawtext=fontfile=$FONT:text='COVER':fontsize=64:fontcolor=white:x=(w-tw)/2:y=(h-th)/2" -frames:v 1 /tmp/fb_cover.png
"${FF[@]}" -f lavfi -i "gradients=size=400x600:c0=0x0f2027:c1=0x2c5364:duration=1:speed=0.01,drawtext=fontfile=$FONT:text='POSTER':fontsize=60:fontcolor=white:x=(w-tw)/2:y=(h-th)/2" -frames:v 1 "$OUT/Mit Poster/poster.jpg"

# 1 MP4 · H.264 + AAC · Kapitel · eingebettetes Cover
"${FF[@]}" -f lavfi -i "$(src testsrc2 'MP4 H.264')" -f lavfi -i "$(tone 440)" -i "$META" -i /tmp/fb_cover.png \
    -map 0:v -map 1:a -map 3:v -map_metadata 2 -map_chapters 2 \
    -c:v:0 libx264 -pix_fmt yuv420p -profile:v:0 high -preset veryfast -crf 30 -c:a aac -b:a 64k \
    -c:v:1 png -disposition:v:1 attached_pic -movflags +faststart "$OUT/Testfilm MP4.mp4"
# Externe Untertitel zum MP4
cat > "$OUT/Testfilm MP4.de.srt" <<'EOF'
1
00:00:00,500 --> 00:00:02,500
Erster Untertitel

2
00:00:03,000 --> 00:00:05,500
Zweiter Untertitel – mit Umlauten: äöü ß
EOF

# 2 MP4 · HEVC (hvc1) + AAC
"${FF[@]}" -f lavfi -i "$(src smptehdbars 'MP4 HEVC')" -f lavfi -i "$(tone 523)" \
    -c:v libx265 -tag:v hvc1 -pix_fmt yuv420p -preset veryfast -crf 32 -x265-params log-level=error \
    -c:a aac -b:a 64k -movflags +faststart "$OUT/Testfilm MP4 (HEVC).mp4"

# 3 M4V · H.264 + AAC
"${FF[@]}" -f lavfi -i "$(src mandelbrot 'M4V')" -f lavfi -i "$(tone 587)" \
    -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a aac -b:a 64k -f mp4 "$OUT/Testfilm M4V.m4v"

# 4 MOV · H.264 + AAC
"${FF[@]}" -f lavfi -i "$(src testsrc2 'MOV')" -f lavfi -i "$(tone 659)" \
    -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a aac -b:a 64k "$OUT/Testfilm MOV.mov"

# 5 MKV · H.264 + zwei Tonspuren (AAC deutsch, AC-3 englisch) + SRT-Untertitel + Kapitel
SRT="$(mktemp --suffix=.srt)"
printf '1\n00:00:01,000 --> 00:00:04,000\nEingebetteter Untertitel\n' > "$SRT"
"${FF[@]}" -f lavfi -i "$(src smptehdbars 'MKV')" -f lavfi -i "$(tone 698)" -f lavfi -i "$(tone 330)" -i "$SRT" -i "$META" \
    -map 0:v -map 1:a -map 2:a -map 3:s -map_metadata 4 -map_chapters 4 \
    -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a:0 aac -b:a:0 64k -c:a:1 ac3 -b:a:1 96k -c:s srt \
    -metadata:s:a:0 language=ger -metadata:s:a:1 language=eng -metadata:s:s:0 language=ger "$OUT/Testfilm MKV.mkv"

# 6 AVI · MPEG-4 Part 2 (Xvid) + MP3
"${FF[@]}" -f lavfi -i "$(src testsrc2 'AVI')" -f lavfi -i "$(tone 784)" \
    -c:v libxvid -q:v 8 -c:a libmp3lame -b:a 64k "$OUT/Testfilm AVI.avi"

# 7 WMV · Windows Media Video 8 + WMA 2
"${FF[@]}" -f lavfi -i "$(src smptehdbars 'WMV')" -f lavfi -i "$(tone 880)" \
    -c:v wmv2 -b:v 300k -c:a wmav2 -b:a 64k "$OUT/Testfilm WMV.wmv"

# 8 MPG · MPEG-2 + MP2 (Programmstrom)
"${FF[@]}" -f lavfi -i "$(src mandelbrot 'MPG')" -f lavfi -i "$(tone 494)" \
    -c:v mpeg2video -b:v 600k -c:a mp2 -b:a 128k -f mpeg "$OUT/Testfilm MPG.mpg"

# 9 MPEG · MPEG-1 + MP2
"${FF[@]}" -f lavfi -i "$(src testsrc2 'MPEG')" -f lavfi -i "$(tone 392)" \
    -c:v mpeg1video -b:v 600k -c:a mp2 -b:a 128k -f mpeg "$OUT/Testfilm MPEG.mpeg"

# 10 TS · H.264 + AAC (MPEG-Transportstrom)
"${FF[@]}" -f lavfi -i "$(src smptehdbars 'TS')" -f lavfi -i "$(tone 349)" \
    -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a aac -b:a 64k -f mpegts "$OUT/Testfilm TS.ts"

# 11 MTS · H.264 + AC-3 (AVCHD-Kamera-Format)
"${FF[@]}" -f lavfi -i "$(src testsrc2 'MTS')" -f lavfi -i "$(tone 370)" \
    -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a ac3 -b:a 96k -f mpegts -mpegts_m2ts_mode 1 "$OUT/Serien/Staffel 1/Kamera 00001.mts"

# 12 M2TS · H.264 + AC-3 (Blu-ray-Transportstrom)
"${FF[@]}" -f lavfi -i "$(src mandelbrot 'M2TS')" -f lavfi -i "$(tone 415)" \
    -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a ac3 -b:a 96k -f mpegts -mpegts_m2ts_mode 1 "$OUT/Testfilm M2TS.m2ts"

# 13 WEBM · VP9 + Opus
"${FF[@]}" -f lavfi -i "$(src testsrc2 'WEBM')" -f lavfi -i "$(tone 466)" \
    -c:v libvpx-vp9 -b:v 200k -deadline realtime -cpu-used 8 -c:a libopus -b:a 48k "$OUT/Testfilm WEBM.webm"

# 14 FLV · Sorenson Spark + MP3
"${FF[@]}" -f lavfi -i "$(src smptehdbars 'FLV')" -f lavfi -i "$(tone 554)" \
    -c:v flv -b:v 300k -c:a libmp3lame -b:a 64k -ar 44100 "$OUT/Testfilm FLV.flv"

# Film mit Poster im eigenen Ordner + Folgen einer „Serie“
"${FF[@]}" -f lavfi -i "$(src testsrc2 'Poster')" -f lavfi -i "$(tone 440)" \
    -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a aac -b:a 64k -movflags +faststart "$OUT/Mit Poster/Film mit Poster.mp4"
for n in 1 2; do
    "${FF[@]}" -f lavfi -i "$(src mandelbrot "Folge $n")" -f lavfi -i "$(tone 300)" \
        -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a aac -b:a 64k -movflags +faststart \
        "$OUT/Serien/Staffel 1/Serie S01E0$n.mp4"
done

# Längerer Film (4 Minuten, sehr kleine Datenrate) – für „Weiterschauen“ (Positionen ab 10 Sekunden)
"${FF[@]}" -f lavfi -i "testsrc2=size=256x144:rate=5,trim=duration=240,drawtext=fontfile=$FONT:text='Langer Testfilm':fontsize=18:fontcolor=white:borderw=2:bordercolor=black:x=(w-tw)/2:y=(h-th)/2-8,drawtext=fontfile=$FONT:text='%{pts\\:hms}':fontsize=12:fontcolor=white:borderw=2:bordercolor=black:x=(w-tw)/2:y=h-22" \
    -f lavfi -i "sine=frequency=220:sample_rate=22050:duration=240" \
    -c:v libx264 -pix_fmt yuv420p -preset veryslow -crf 40 -g 250 -c:a aac -b:a 24k -ac 1 -movflags +faststart "$OUT/Langer Testfilm (2026).mp4"

# Kaputte und unpassende Dateien (dürfen nie zum Absturz führen)
head -c 65536 /dev/urandom > "$OUT/Kaputt/Zufallsdaten.mp4"
: > "$OUT/Kaputt/Leere Datei.mkv"
head -c 20000 "$OUT/Testfilm MKV.mkv" > "$OUT/Kaputt/Abgeschnitten.mkv"
printf 'Das ist kein Video.\n' > "$OUT/Kaputt/Textdatei.avi"
# Mac-Hilfsdateien, die der Scanner überspringen muss
cp "$OUT/Testfilm MOV.mov" "$OUT/._Testfilm.mov"
printf 'x' > "$OUT/.DS_Store"
mkdir -p "$OUT/.Trashes"
cp "$OUT/Testfilm M4V.m4v" "$OUT/.Trashes/Geloescht.m4v"
# Paket (Fotos-Mediathek ist auf jedem Mac als Paket bekannt) – Inhalt wird nicht durchsucht
mkdir -p "$OUT/Mediathek.photoslibrary/originals"
cp "$OUT/Testfilm M4V.m4v" "$OUT/Mediathek.photoslibrary/originals/Im Paket.m4v"

rm -f "$META" "$SRT" /tmp/fb_cover.png
echo "▸ Testvideos:"
find "$OUT" -type f | sort | while read -r f; do printf '  %8s  %s\n' "$(stat -c %s "$f")" "${f#$OUT/}"; done
du -sh "$OUT"
