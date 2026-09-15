`timescale 1ns / 1ps

module fp4_mul(a,b,y);

input [3:0] a,b;
output reg [7:0]y;

wire [2:0]expa,expb;
wire [3:0]mant;
wire [2:0]sum1;
wire [3:0]sum2;
reg [3:0]sum3;
reg [3:0]shift;

wire a0,a1,b0,b1;

reg [2:0]mant_final;



assign expa = (a[2:1]==2'b00)?3'b000:{1'b0,a[2:1]}+ 3'b111;
assign expb = (b[2:1]==2'b00)?3'b000:{1'b0,b[2:1]}+ 3'b111;

assign a1 = |a[2:1];
assign b1 = |b[2:1];

assign a0 = a[0];
assign b0 = b[0];

assign mant[0] = (a0&b0);
assign mant[1] = (a1&b0)^(a0&b1);
assign mant[2] = ((a1&b0)&(a0&b1)) ^ (a1&b1) ;
assign mant[3] = ((a1&b0)&(a0&b1)) & (a1&b1) ;

assign sum1 = expa + expb ;
assign sum2 = (a[2:0] == 3'b000 || b[2:0] == 3'b000 )?4'b0000: sum1 + 4'b0111;


always@(*)
begin
y = 8'd0;
sum3 = 4'b0;
mant_final = 3'b000;
shift = 4'b0000;


      if(mant[3] == 1'b1 )
        begin
             mant_final = mant[2:0];
             shift = 4'b0001;
        end
      
       else if(mant[2] == 1'b1 )
          begin 
             mant_final = {mant[1:0],1'd0};
               shift = 4'b0000;
             
          end
       
      else if(mant[1] == 1'b1 )
          begin 
            mant_final = {mant[0],2'd0};
              shift = 4'b1111;
             
          end 
     
      else if(mant[0] == 1'b1 )
          begin 
              mant_final = {3'd0};
               shift = 4'b1110;
             
          end
          
      sum3 = sum2  +  shift;
      y ={a[3]^b[3],sum3[3:0] , mant_final};
          

end
endmodule
