#!/usr/bin/env bash

TEST_STRING=${TEST_STRING:-"In short, Malcolm provides an easily deployable network analysis tool suite for full packet capture artifacts (pee-cap files) and Zeek logs."}

for VOICE in $(mimic3 --voices | grep ^en | awk '{print $1}'); do
    for SPEAKER in $( (curl -fsSL "https://raw.githubusercontent.com/MycroftAI/mimic3-voices/master/voices/${VOICE}/speakers.txt" 2>/dev/null || echo 'default' ) | tr '\r' '\n' ); do
        OUTFILE="$(echo "${VOICE}_${SPEAKER}" | tr -cd '[:alnum:]._-')"
        echo "${OUTFILE}"
        tee "${OUTFILE}.ssml" >/dev/null <<EOF
<speak>
  <voice name="${VOICE}#${SPEAKER}">
    Ozymandias
    <break time="1s"/>
    by Percy Bysshe Shelley.
    <break time="2s"/>
    I met a traveller from an antique land,
    Who said, "Two vast and trunkless legs of stone
    Stand in the desert. . . . Near them, on the sand,
    Half sunk a shattered visage lies, whose frown,
    And wrinkled lip, and sneer of cold command,
    Tell that its sculptor well those passions read
    Which yet survive, stamped on these lifeless things,
    The hand that mocked them, and the heart that fed;
    And on the pedestal, these words appear:
    My name is Ozymandias, King of Kings;
    Look on my Works, ye Mighty, and despair!
    Nothing beside remains. Round the decay
    Of that colossal Wreck, boundless and bare
    The lone and level sands stretch far away."
    <break time="5s"/>
    This voice was ${VOICE} with the speaker ${SPEAKER}.
  </voice>
</speak>
EOF
        mimic3 --ssml >"${OUTFILE}.wav" <"${OUTFILE}.ssml" 2>/dev/null && \
            ffmpeg -hide_banner -loglevel error -y -i "${OUTFILE}.wav" -c:a libvorbis -qscale:a 5 -ar 44100 -ac 1 "${OUTFILE}.ogg" && \
            rm -f "${OUTFILE}.wav" "${OUTFILE}.ssml"
    done
done
