"""Simulateur de lancers : vise le T20 avec une dispersion gaussienne, 3 fléchettes par tour,
puis retire les fléchettes. Ne lance que quand le hub annonce une partie en cours."""

import json
import os
import random
import threading
import time

from dartlink import (
    DART_TOPIC, MQTT_HOST, MQTT_PORT, STATE_TOPIC, STATUS_TOPIC, TAKEOUT_TOPIC, VERSION,
    dart_at, dart_message, new_client, segment_name, target_point,
)

# Dispersion du lanceur en mm (écart type), réglable par SIM_SPREAD.
SPREAD = float(os.environ.get("SIM_SPREAD", "20"))

playing = threading.Event()


def status(state):
    return json.dumps({"state": state, "mode": "sim", "version": VERSION})


def on_connect(client, userdata, flags, reason_code, properties):
    print(f"connecté à {MQTT_HOST} ({reason_code})", flush=True)
    client.subscribe(STATE_TOPIC, qos=1)
    client.publish(STATUS_TOPIC, status("online"), qos=1, retain=True)


def on_message(client, userdata, msg):
    try:
        on = bool(json.loads(msg.payload).get("playing"))
    except (ValueError, AttributeError):
        on = False
    print(f"hub : partie {'en cours' if on else 'arrêtée'}", flush=True)
    (playing.set if on else playing.clear)()


def throw(client):
    x0, y0 = target_point(20, 3)
    x, y = random.gauss(x0, SPREAD), random.gauss(y0, SPREAD)
    n, m = dart_at(x, y)
    client.publish(DART_TOPIC, dart_message(n, m, x, y), qos=1)
    print(f"fléchette {segment_name(n, m)}", flush=True)


def main():
    client = new_client("dartos-cam-sim")
    client.will_set(STATUS_TOPIC, status("offline"), qos=1, retain=True)
    client.on_connect = on_connect
    client.on_message = on_message
    client.reconnect_delay_set(1, 30)
    client.connect_async(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()
    try:
        while True:
            playing.wait()
            time.sleep(3)
            darts = 0
            while darts < 3 and playing.is_set():
                throw(client)
                darts += 1
                if darts < 3:
                    time.sleep(random.uniform(2, 4))
            if darts == 0:
                continue
            time.sleep(5)
            client.publish(TAKEOUT_TOPIC, json.dumps({"ts": int(time.time() * 1000)}), qos=1)
            print("fléchettes retirées", flush=True)
    finally:
        client.publish(STATUS_TOPIC, status("offline"), qos=1, retain=True).wait_for_publish(2)
        client.loop_stop()


if __name__ == "__main__":
    main()
