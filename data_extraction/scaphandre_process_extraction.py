import json

file_path = "scaphandre_json"
total_energy_uWs = 0
sampling_interval_seconds = 2  # Each JSON line represents a 2s interval

with open(file_path, "r") as file:
    for line in file:
        try:
            data = json.loads(line.strip())
            interval_energy = 0
            for consumer in data.get("consumers", []):
                cmdline = consumer.get("cmdline", "").lower()
                if "chia" in cmdline:
                    power_uW = consumer.get("consumption", 0)
                    interval_energy += power_uW
            total_energy_uWs += interval_energy * sampling_interval_seconds
        except json.JSONDecodeError:
            print("Skipping invalid JSON line")

# Convert µW·s to kWh: 1 kWh = 3.6e12 µW·s
total_energy_kWh = total_energy_uWs / 3.6e12

print(f"Chia Energy Consumption (kWh): {total_energy_kWh:.6f}")
