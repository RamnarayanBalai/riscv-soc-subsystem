module uart_axi (
  input clk, input reset,
  input [31:0] awaddr, input awvalid, output reg awready,
  input [31:0] wdata, input [3:0] wstrb, input wvalid, output reg wready,
  output reg [1:0] bresp, output reg bvalid, input bready,
  input [31:0] araddr, input arvalid, output reg arready,
  output reg [31:0] rdata, output reg [1:0] rresp, output reg rvalid, input rready,
  output tx_pin, input rx_pin
);
  reg [7:0] tx_buf;
  reg tx_start;
  wire tx_busy;
  
  uart_tx u_tx (.clk(clk), .rst_n(~reset), .tx_en(tx_start), .tx_data(tx_buf), .tx_out(tx_pin), .tx_busy(tx_busy));
  
  always @(posedge clk) begin
    if (reset) begin
      awready <= 0; wready <= 0; bvalid <= 0; bresp <= 0; tx_start <= 0;
      arready <= 0; rvalid <= 0; rresp <= 0; rdata <= 0;
    end else begin
      tx_start <= 0;
      if (awvalid && !awready) awready <= 1; else awready <= 0;
      if (wvalid && !wready) wready <= 1; else wready <= 0;
      if (awready && wready) begin
        bvalid <= 1;
        if (awaddr[7:0] == 8'h00) begin
          tx_buf <= wdata[7:0];
          tx_start <= 1;
        end
      end
      if (bvalid && bready) bvalid <= 0;

      if (arvalid && !arready && !rvalid) begin
        arready <= 1;
        if (araddr[7:0] == 8'h08) rdata <= {31'b0, tx_busy};
        else rdata <= 32'h0;
        rvalid <= 1;
      end else begin
        arready <= 0;
      end
      if (rvalid && rready) rvalid <= 0;
    end
  end
endmodule
