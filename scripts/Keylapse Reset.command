#!/bin/bash
# Keylapse back to before its first launch: quits it, takes back its Accessibility and
# Input Monitoring permissions and forgets its settings. The app stays where it is;
# open it yourself afterwards to see the welcome page again.
ID=com.openchamber.keylapse
osascript -e 'tell application "Keylapse" to quit' >/dev/null 2>&1
sleep 1
tccutil reset Accessibility "$ID"
tccutil reset ListenEvent "$ID"
defaults delete "$ID" >/dev/null 2>&1 && echo "Settings forgotten." || echo "No settings were stored."
echo
echo "Done. Open Keylapse to see its first launch again."
