RTL = rtl
TB = tb
FW = fw

all: soc

fw:
	$(MAKE) -C $(FW)

soc: fw
	verilator --binary -j 0 -Wno-DECLFILENAME -Wno-PINMISSING -Wno-GENUNNAMED -Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-SYNCASYNCNET $(RTL)/picorv32.v $(RTL)/top.v $(RTL)/axi_lite_interconnect.v $(RTL)/axi_decoder.v $(RTL)/rom.v $(RTL)/sram.v $(RTL)/uart_axi.v $(RTL)/uart_tx.v $(RTL)/uart_rx.v $(TB)/tb_top.v --top tb_top --timing --CFLAGS "-std=c++20" --trace
	./obj_dir/Vtb_top +romhex=$(RTL)/rom.hex

synth:
	yosys -D SYNTHESIS -p 'synth_design -top top' $(RTL)/picorv32.v $(RTL)/top.v $(RTL)/axi_lite_interconnect.v $(RTL)/axi_decoder.v $(RTL)/rom.v $(RTL)/sram.v $(RTL)/uart_axi.v $(RTL)/uart_tx.v $(RTL)/uart_rx.v

clean:
	rm -rf obj_dir *.vcd *.fst
	$(MAKE) -C $(FW) clean
