#!/bin/zsh

CLIENT_ID="212557"
CLIENT_SECRET="5c47a54e7393262025cbde277eb033cedcf9a68c"
VERIFY_TOKEN="AIFitnessCoachSecret2026"

echo "🚀 1. Start AI Fitness Coach Backend..."
node server.js &
NODE_PID=$!

echo "🌐 2. Start ngrok tunnel op poort 3000..."
ngrok http 3000 > /dev/null 2>&1 &
NGROK_PID=$!

sleep 3

NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o '"public_url":"https://[^"]*' | grep -o 'https://.*')

if [ -z "$NGROK_URL" ]; then
    echo "❌ Fout: Kon de ngrok URL niet ophalen."
    kill $NODE_PID
    kill $NGROK_PID
    exit 1
fi

echo "✅ Ngrok URL gevonden: $NGROK_URL"
echo "🔍 3. Controleren op oude Strava webhooks..."

SUBS=$(curl -s -X GET "https://www.strava.com/api/v3/push_subscriptions?client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET")
OLD_ID=$(echo $SUBS | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -n 1)

if [ ! -z "$OLD_ID" ]; then
    echo "🗑️ Oude webhook gevonden (ID: $OLD_ID). Wordt nu verwijderd..."
    curl -s -X DELETE "https://www.strava.com/api/v3/push_subscriptions/$OLD_ID?client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET"
fi

echo "🚀 4. Nieuwe webhook registreren bij Strava..."
curl -s -X POST https://www.strava.com/api/v3/push_subscriptions \
  -F client_id=$CLIENT_ID \
  -F client_secret=$CLIENT_SECRET \
  -F callback_url=$NGROK_URL/webhook \
  -F verify_token=$VERIFY_TOKEN | grep -o '"id":[0-9]*'

echo "\n\n🎉 BOOM! Alles draait perfect. Je app luistert nu naar Strava."
echo "⚠️  Druk op Ctrl+C om de server en ngrok straks netjes af te sluiten."

trap "echo '\n🔴 Alles afsluiten...'; kill $NODE_PID; kill $NGROK_PID; exit 0" INT TERM

wait $NODE_PID
