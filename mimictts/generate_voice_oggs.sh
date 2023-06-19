#!/usr/bin/env bash

TEST_STRING=${TEST_STRING:-"In short, Malcolm provides an easily deployable network analysis tool suite for full packet capture artifacts (pee-cap files) and Zeek logs."}

for VOICE in $(mimic3 --voices | grep ^en | awk '{print $1}'); do
    for SPEAKER in $( (curl -fsSL "https://raw.githubusercontent.com/MycroftAI/mimic3-voices/master/voices/${VOICE}/speakers.txt" 2>/dev/null || echo 'default' ) | tr '\r' '\n' ); do
        OUTFILE="$(echo "${VOICE}_${SPEAKER}" | tr -cd '[:alnum:]._-')"
        echo "${OUTFILE}"
        tee "${OUTFILE}.ssml" >/dev/null <<EOF
<speak>
  <voice name="${VOICE}#${SPEAKER}">
    <s>
      ${TEST_STRING}
    </s>
    <break time="1s"/>
    <s>
      This voice was ${VOICE} with the speaker ${SPEAKER}.
    </s>
  </voice>
</speak>
EOF
        mimic3 --ssml >"${OUTFILE}.wav" 2>/dev/null <"${OUTFILE}.ssml" && \
            ffmpeg -hide_banner -loglevel error -y -i "${OUTFILE}.wav" -c:a libvorbis -qscale:a 5 -ar 44100 -ac 1 "${OUTFILE}.ogg" && \
            rm -f "${OUTFILE}.wav" "${OUTFILE}.ssml"
    done
done
