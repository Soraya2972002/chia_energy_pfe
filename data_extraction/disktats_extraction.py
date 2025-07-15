import re

def extract_stats(line):
            fields = line.strip().split()
            print(fields)
            writes_completed = int(fields[9])
            sectors_written = int(fields[11])
            return writes_completed, sectors_written

def main():
    with open("chia_io.log", "r") as f:
        lines = f.readlines()

    # Split into initial and final stat sections
    initial_line = ""
    final_line = ""

    for line in lines:
        if initial_line == "": 
                initial_line=line
        final_line=line
    print(final_line,initial_line)
    # Extract data for sda5
    init_writes, init_sectors = extract_stats(initial_line)
    final_writes, final_sectors = extract_stats(final_line)

    if None in [init_writes, final_writes, init_sectors, final_sectors]:
        print("Error: Could not parse initial or final stats for sda5")
        return

    delta_writes = final_writes - init_writes
    delta_sectors = final_sectors - init_sectors
    bytes_written = delta_sectors * 512
    tb_written = bytes_written / 1e12

    print(f"Write operations: {delta_writes}")
    print(f"Bytes written: {bytes_written} bytes = {tb_written:.4f} TB")

if __name__ == "__main__":
    main()
