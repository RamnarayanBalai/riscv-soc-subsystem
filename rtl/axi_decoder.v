module axi_decoder (
  input  [31:0] addr,
  output reg [2:0] sel
);
  always @(*) begin
    casez (addr)
      32'h0000_????: sel = 3'b001; // ROM
      32'h0001_????: sel = 3'b010; // SRAM
      32'h1000_000?: sel = 3'b100; // UART
      default:       sel = 3'b001; // Default safe
    endcase
  end
endmodule
