package require openlane 0.9

# Prepare the design using the config.json in the current directory
prep -design . -overwrite

# Run the entire physical design flow sequentially
run_synthesis
run_floorplan
run_placement
run_cts
run_routing
run_magic
run_magic_spice_export
run_magic_drc
run_lvs
run_antenna_check

# Exit the interactive session
exit
