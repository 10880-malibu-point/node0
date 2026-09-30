#!/usr/bin/env python3
"""
phone_state_track.py - Track Utkarsh's phone state: sleep/wake, location, charging.

STATE INFERENCE (time-windowed, not single-snapshot):
A single tick can't tell awake from asleep - the COMBINATION of signals must
PERSIST over a sensible window before we conclude a state. This follows the
Sleep-as-Android awake-detection heuristics:

  AWAKE signals (any one, sustained):
    - Screen ON (definitive - user is using the phone)
    - Motion intensity > 0.15G (medium sensitivity, Sleep as Android)
    - Ambient light > 60 lux (medium sensitivity) - room lights on
  ASLEEP signals (all together, sustained):
    - Screen OFF
    - No significant motion
    - Low light (< 30 lux) - room dark

We classify each tick, then look at the LAST WINDOW (default 15 min) of ticks.
If >= 70% of ticks in the window agree on a state, we conclude that state.
This avoids false conclusions from a single blip (e.g. grabbing the phone to
check the time, a light flickering on for a minute).

Signals captured every 60s on the phone (sensor_capture.sh):
  - battery (status, plugged, percentage)
  - accel (icm456xx Accelerometer) - motion
  - light (OPLUS Fusion Light Sensor) - ambient lux
  - location (network) - lat/lon

Known safe locations: (lat, lon, radius_m, label)
  - Hotel Orion, Junagarh (current)
  - Bokaro
"""
import json, os, re, subprocess, sys
from datetime import datetime, timezone, timedelta

STATE_DIR = "/opt/data"
STATE_LOG = os.path.join(STATE_DIR, "phone_state.log")
STATE_JSON = os.path.join(STATE_DIR, "phone_state.json")
SENSOR_LOG = os.path.join(STATE_DIR, "phone_sensor_data.log")

IST = timezone(timedelta(hours=5, minutes=30))

# Known safe locations: (lat, lon, radius_m, label)
KNOWN_LOCS = [
    (19.8645, 82.9442, 500, "Hotel Orion, Junagarh"),
    (23.7870, 85.9700, 500, "Bokaro"),
]

# Sleep as Android thresholds (medium sensitivity)
LIGHT_AWAKE_LUX = 60.0   # light over this = awake
LIGHT_DARK_LUX = 30.0     # light under this = dark (asleep-friendly)
MOTION_AWAKE_G = 0.15    # motion intensity over this = awake
WINDOW_MIN = 15          # look back this many minutes
AGREE_RATIO = 0.7        # fraction of window ticks that must agree


def read_sensor_entries():
    """Parse the multi-line JSON sensor log into a list of dicts."""
    if not os.path.exists(SENSOR_LOG):
        return []
    data = open(SENSOR_LOG).read()
    entries = re.split(r'\n(?=\{"ts":)', data)
    out = []
    for e in entries:
        if not e.strip().startswith('{"ts":'):
            continue
        try:
            out.append(json.loads(e))
        except Exception:
            pass
    return out


def get_screen_state():
    """Read phone screen state via sys0 adb. Returns (awake, screen_on) or None."""
    try:
        r = subprocess.run(
            ["ssh", "-i", "/opt/data/home/.ssh/id_ed25519",
             "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=8",
             "hermes@10.7.0.2",
             "adb -s 192.168.1.150:5555 shell \"dumpsys power | grep -E 'mWakefulness=' | head -1; dumpsys display | grep -E 'mScreenState=' | head -1\""],
            capture_output=True, text=True, timeout=20)
        out = r.stdout
        awake = "mWakefulness=Awake" in out
        screen_on = "mScreenState=ON" in out
        return awake, screen_on
    except Exception:
        return None


def nearest_loc(lat, lon):
    """Return label of nearest known location if within radius, else 'elsewhere'."""
    if lat is None or lon is None:
        return "unknown"
    best = None
    best_d = float('inf')
    for (klat, klon, rad, label) in KNOWN_LOCS:
        d = ((lat - klat) ** 2 + (lon - klon) ** 2) ** 0.5 * 111000  # approx meters
        if d < rad and d < best_d:
            best_d = d
            best = label
    return best if best else "elsewhere"


def classify_tick(e, screen):
    """
    Classify a single tick as 'awake' or 'asleep' based on the combination of
    signals. Returns (state, reasons) where reasons lists which signals fired.
    """
    reasons = []

    # Screen state (definitive)
    if screen:
        screen_on = screen[1]
        if screen_on:
            reasons.append("screen_on")

    # Motion: accel magnitude deviation from gravity (~9.8)
    a = e.get('accel')
    if a and a != 'null':
        try:
            vals = a.get('icm456xx Accelerometer Non-wakeup', {}).get('values', [])
            if len(vals) == 3:
                mag = (vals[0]**2 + vals[1]**2 + vals[2]**2) ** 0.5
                dev = abs(mag - 9.8)
                if dev > MOTION_AWAKE_G:
                    reasons.append("motion")
        except Exception:
            pass

    # Light
    light = e.get('light')
    lux = None
    light_known = False
    if light and light != 'null':
        try:
            vals = light.get('OPLUS Fusion Light Sensor', {}).get('values', [])
            if vals:
                lux = vals[0]
                light_known = True
                if lux > LIGHT_AWAKE_LUX:
                    reasons.append("light")
        except Exception:
            pass

    # Classify:
    #   awake if ANY awake signal fired
    #   asleep only if we have light data showing it's dark (screen off + no motion
    #     + dark). If light is UNKNOWN, we can't confirm darkness, so the tick is
    #     'unknown' - missing light data must NOT count as a dark/asleep signal.
    if reasons:
        return "awake", reasons, lux
    if light_known and lux is not None and lux < LIGHT_DARK_LUX:
        return "asleep", reasons, lux
    return "unknown", reasons, lux


def main():
    entries = read_sensor_entries()
    now = datetime.now(IST)

    # Latest battery
    battery = None
    for e in reversed(entries):
        if e.get('battery'):
            battery = e['battery']
            break

    # Latest location
    loc = None
    for e in reversed(entries):
        if e.get('location') and e['location'] != 'null':
            loc = e['location']
            break

    # Screen state (current)
    screen = get_screen_state()

    # Build the window: ticks within the last WINDOW_MIN minutes
    window = []
    cutoff = now - timedelta(minutes=WINDOW_MIN)
    for e in entries:
        try:
            ts = datetime.fromisoformat(e['ts'])
        except Exception:
            continue
        if ts >= cutoff:
            window.append(e)

    # Classify each tick in the window
    tick_states = []
    for e in window:
        state, reasons, lux = classify_tick(e, screen)
        tick_states.append(state)

    # Conclude based on persistence over the window.
    # 'unknown' ticks (missing light data) don't count toward either state.
    if not tick_states:
        sleep_state = "unknown"
        confidence = 0.0
    else:
        awake_count = tick_states.count("awake")
        asleep_count = tick_states.count("asleep")
        known = awake_count + asleep_count
        if known == 0:
            sleep_state = "unknown"
            confidence = 0.0
        else:
            awake_ratio = awake_count / known
            asleep_ratio = asleep_count / known
            if awake_ratio >= AGREE_RATIO:
                sleep_state = "awake"
                confidence = awake_ratio
            elif asleep_ratio >= AGREE_RATIO:
                sleep_state = "asleep"
                confidence = asleep_ratio
            else:
                sleep_state = "transition"  # mixed window, no clear state
                confidence = max(awake_ratio, asleep_ratio)

    # Location context
    lat = loc.get('latitude') if loc else None
    lon = loc.get('longitude') if loc else None
    place = nearest_loc(lat, lon)

    # Charging
    charging = False
    if battery:
        charging = battery.get('status') == 'CHARGING' or battery.get('plugged') != 'UNPLUGGED'

    # Safety/private inference: charging + at known location = in rooms
    private = charging and place in ("Hotel Orion, Junagarh", "Bokaro")

    # Latest light for context
    latest_lux = None
    for e in reversed(entries):
        light = e.get('light')
        if light and light != 'null':
            try:
                vals = light.get('OPLUS Fusion Light Sensor', {}).get('values', [])
                if vals:
                    latest_lux = vals[0]
                    break
            except Exception:
                pass

    state = {
        "ts": now.isoformat(),
        "sleep_state": sleep_state,
        "confidence": round(confidence, 2),
        "window_min": WINDOW_MIN,
        "ticks_in_window": len(tick_states),
        "awake_ticks": tick_states.count("awake"),
        "asleep_ticks": tick_states.count("asleep"),
        "screen_on": screen[1] if screen else None,
        "motion": "motion" in [r for _, r, _ in [classify_tick(e, screen) for e in window[-1:]]] if window else None,
        "light_lux": latest_lux,
        "place": place,
        "lat": lat,
        "lon": lon,
        "charging": charging,
        "battery_pct": battery.get('percentage') if battery else None,
        "private_safe": private,
    }

    # Append to log (one line per tick)
    with open(STATE_LOG, "a") as f:
        f.write(json.dumps(state) + "\n")

    # Write current state JSON
    with open(STATE_JSON, "w") as f:
        json.dump(state, f, indent=2)

    # Keep log bounded (~2000 lines)
    try:
        lines = open(STATE_LOG).readlines()
        if len(lines) > 2000:
            with open(STATE_LOG, "w") as f:
                f.writelines(lines[-2000:])
    except Exception:
        pass

    # Silent on success (no_agent cron). Print nothing.

if __name__ == "__main__":
    main()
