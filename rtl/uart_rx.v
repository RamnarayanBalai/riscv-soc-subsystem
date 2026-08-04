module uart_rx (
  input clk, input rst_n, input rx_in,
  output reg [7:0] rx_data, output reg rx_valid
);
  // Placeholder - not actively used in this simulation demo
  always @(posedge clk) begin
     rx_valid <= 0;
  end
endmodule
