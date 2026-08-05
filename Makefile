RTL = rtl
TB = tb
FW = fw

all: soc
.PHONY: all fw soc synth clean

fw:
	$(MAKE) -C $(FW)

soc: fw
	verilator --binary -j 0 -Wno-DECLFILENAME -Wno-PINMISSING -Wno-GENUNNAMED -Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-SYNCASYNCNET $(RTL)/picorv32.v $(RTL)/top.v $(RTL)/axi_lite_interconnect.v $(RTL)/axi_decoder.v $(RTL)/rom.v $(RTL)/sram.v $(RTL)/uart_axi.v $(RTL)/uart_tx.v $(RTL)/uart_rx.v $(TB)/tb_top.v --top tb_top --timing --CFLAGS "-std=c++20" --trace
	./obj_dir/Vtb_top +romhex=$(RTL)/rom.hex

synth:
	yosys -D SYNTHESIS -p 'synth -top top' $(RTL)/picorv32.v $(RTL)/top.v $(RTL)/axi_lite_interconnect.v $(RTL)/axi_decoder.v $(RTL)/rom.v $(RTL)/sram.v $(RTL)/uart_axi.v $(RTL)/uart_tx.v $(RTL)/uart_rx.v

run_flow:
	@echo "================================================================"
	@echo "To run OpenLane in this Virtual Lab, please run the following:"
	@echo "1. Start the OpenLane shell:"
	@echo "   openlane shell"
	@echo "2. Inside the shell, run the automated flow:"
	@echo "   ./flow.tcl -design /home/lab-user/riscv-soc-subsystem/openlane_design"
	@echo "   -- OR for interactive mode --"
	@echo "   ./flow.tcl -interactive -file /home/lab-user/riscv-soc-subsystem/openlane_design/flow_commands.tcl"
	@echo "================================================================"

pull:
	git fetch origin
	git pull origin master

clean:
	rm -rf obj_dir *.vcd *.fst runs/ openlane_design/runs/
	$(MAKE) -C $(FW) clean
