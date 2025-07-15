# Load watt values from text file (one per line)
with open("power_values.txt", "r") as file:
    watt_values = [float(line.strip()) for line in file]

# Calculate total energy
total_wh = sum(watt * 0.01 / 3600 for watt in watt_values)
print(f"Total Energy Consumption: {total_wh:.4f} Wh")
