import json

def calculate_host_energy(file_path):
    total_energy_uj = 0  # Total energy in microjoules
    prev_time = None

    with open(file_path, 'r') as file:
        for line in file:
            try:
                data = json.loads(line)
                current_time = data["host"]["timestamp"]
                host_power_uw = data["host"]["consumption"]  # in µW

                if prev_time is not None:
                    interval = current_time - prev_time  # seconds
                    total_energy_uj += host_power_uw * interval  # µJ = µW × s

                prev_time = current_time
            except Exception as e:
                print(f"Skipping line due to error: {e}")

    # Convert µJ to kWh: 1 kWh = 3.6e12 µJ
    return total_energy_uj / 3.6e12

energy_kwh = calculate_host_energy("scaphandre_json")
print(f"Total host energy: {energy_kwh:.6f} kWh")

