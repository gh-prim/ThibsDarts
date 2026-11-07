"""Envoie une fléchette (ou un retrait) à la main.

    python3 throw.py T20        une fléchette (T20, D16, S5, SB, DB, MISS)
    python3 throw.py takeout    fléchettes retirées, fin du tour
"""

import json
import sys
import time

from dartlink import DART_TOPIC, MQTT_HOST, MQTT_PORT, TAKEOUT_TOPIC, dart_message, new_client, parse_segment


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    arg = sys.argv[1]
    if arg.lower() == "takeout":
        topic, payload = TAKEOUT_TOPIC, json.dumps({"ts": int(time.time() * 1000)})
    else:
        topic, payload = DART_TOPIC, dart_message(*parse_segment(arg), source="manual")
    client = new_client("dartos-cam-throw")
    client.connect(MQTT_HOST, MQTT_PORT)
    client.loop_start()
    client.publish(topic, payload, qos=1).wait_for_publish(5)
    client.loop_stop()
    client.disconnect()
    print(payload)


if __name__ == "__main__":
    main()
