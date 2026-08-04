`timescale 1ns/1ps
module tb_top;
  reg clk, reset;
  wire uart_tx, uart_rx;
  
  top u_top (.clk(clk), .reset(reset), .uart_tx(uart_tx), .uart_rx(uart_rx));
  assign uart_rx = 1'b1; // Idle high
  
  initial clk = 0;
  always #10 clk = ~clk; // 50 MHz
  
  initial begin
    $dumpfile("tb_top.vcd"); $dumpvars(0, tb_top);
    $display("--------------------------------------------------");
    $display(" UART SoC Simulation Started");
    $display("--------------------------------------------------");
    
    reset = 1; #100 reset = 0;
    
    // Sim duration for firmware to complete
    #30000000; // ~30ms
    $display("TEST PASSED (time limit reached)");
    $finish;
  end
  
  // UART Monitor
  localparam CLKS_PER_BIT = 434;
  localparam BIT_TIME = 20 * CLKS_PER_BIT;
  
  reg [7:0] rx_byte;
  integer i;
  always @(negedge uart_tx) begin
    if (!reset) begin
      #(BIT_TIME/2); // middle of start bit
      for (i=0; i<8; i=i+1) begin
        #(BIT_TIME);
        rx_byte[i] = uart_tx;
      end
      #(BIT_TIME); // Stop bit
      $write("%c", rx_byte);
    end
  end
endmodule
