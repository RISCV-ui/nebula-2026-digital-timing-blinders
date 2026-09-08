module adder(input [3:0] a, b, output [3:0] y);
  // functionally identical, rewritten
  wire [3:0] tmp;
  assign tmp = a;
  assign y = tmp + b;
endmodule
