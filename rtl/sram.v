module sram (
  input clk, input reset,
  input [31:0] awaddr, input awvalid, output reg awready,
  input [31:0] wdata, input [3:0] wstrb, input wvalid, output reg wready,
  output reg [1:0] bresp, output reg bvalid, input bready,
  input [31:0] araddr, input arvalid, output reg arready,
  output reg [31:0] rdata, output reg [1:0] rresp, output reg rvalid, input rready
);
  reg [31:0] mem [0:63];
  
  wire [5:0] w_addr = awaddr[7:2];
  wire [5:0] r_addr = araddr[7:2];

  always @(posedge clk) begin
    if (reset) begin
      awready <= 0; wready <= 0; bvalid <= 0; bresp <= 0;
      arready <= 0; rvalid <= 0; rresp <= 0; rdata <= 0;
    end else begin
      // Write
      if (awvalid && !awready) awready <= 1; else awready <= 0;
      if (wvalid && !wready) wready <= 1; else wready <= 0;
      if (awready && wready) begin
        bvalid <= 1;
        if (wstrb[0]) mem[w_addr][7:0]   <= wdata[7:0];
        if (wstrb[1]) mem[w_addr][15:8]  <= wdata[15:8];
        if (wstrb[2]) mem[w_addr][23:16] <= wdata[23:16];
        if (wstrb[3]) mem[w_addr][31:24] <= wdata[31:24];
      end
      if (bvalid && bready) bvalid <= 0;

      // Read
      if (arvalid && !arready && !rvalid) begin
        arready <= 1;
        rdata <= mem[r_addr];
        rvalid <= 1;
      end else begin
        arready <= 0;
      end
      if (rvalid && rready) rvalid <= 0;
    end
  end
endmodule
