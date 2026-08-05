module rom (
  input clk, input reset,
  input [31:0] awaddr, input awvalid, output reg awready,
  input [31:0] wdata, input [3:0] wstrb, input wvalid, output reg wready,
  output reg [1:0] bresp, output reg bvalid, input bready,
  input [31:0] araddr, input arvalid, output reg arready,
  output reg [31:0] rdata, output reg [1:0] rresp, output reg rvalid, input rready
);
  reg [31:0] mem [0:2047];
  
`ifdef SYNTHESIS
  initial $readmemh("/home/lab-user/riscv-soc-subsystem/rtl/rom.hex", mem);
`else
  initial $readmemh("rtl/rom.hex", mem);
`endif

  wire [10:0] word_addr = araddr[12:2];

  always @(posedge clk) begin
    if (reset) begin
      awready <= 0; wready <= 0; bvalid <= 0; bresp <= 0;
      arready <= 0; rvalid <= 0; rresp <= 0; rdata <= 0;
    end else begin
      // ROM ignores writes but acks them
      if (awvalid && !awready) awready <= 1; else awready <= 0;
      if (wvalid && !wready) wready <= 1; else wready <= 0;
      if (awready && wready) bvalid <= 1;
      if (bvalid && bready) bvalid <= 0;

      // Read
      if (arvalid && !arready && !rvalid) begin
        arready <= 1;
        rdata <= mem[word_addr];
        rvalid <= 1;
      end else begin
        arready <= 0;
      end
      if (rvalid && rready) rvalid <= 0;
    end
  end
endmodule
