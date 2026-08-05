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
	cd openlane_design && openlane --interactive -file flow_commands.tcl

pull:
	git fetch origin
	git pull origin master

clean:
	rm -rf obj_dir *.vcd *.fst runs/ openlane_design/runs/
	$(MAKE) -C $(FW) clean
