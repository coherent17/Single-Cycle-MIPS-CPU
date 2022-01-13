module SP(
	// INPUT SIGNAL
	clk,
	rst_n,
	in_valid,
	inst,
	mem_dout,
	// OUTPUT SIGNAL
	out_valid,
	inst_addr,
	mem_wen,
	mem_addr,
	mem_din
);

//------------------------------------------------------------------------
//   INPUT AND OUTPUT DECLARATION                         
//------------------------------------------------------------------------

input                    clk, rst_n, in_valid;
input             [31:0] inst;
input  signed     [31:0] mem_dout;
output reg               out_valid;
output reg        [31:0] inst_addr;
output reg               mem_wen;
output reg        [11:0] mem_addr;
output reg signed [31:0] mem_din;

//------------------------------------------------------------------------
//   DECLARATION
//------------------------------------------------------------------------

// REGISTER FILE, DO NOT EDIT THE NAME.
reg	        [31:0] r      [0:31]; 

reg [31:0]inst_buffer;
wire [5:0] opcode = inst_buffer[31:26];
wire [4:0] rs = inst_buffer[25:21];
wire [4:0] rt = inst_buffer[20:16];
wire [4:0] rd = inst_buffer[15:11];
wire [4:0] shamt = inst_buffer[10:6];
wire [5:0] funct = inst_buffer[5:0];
wire [15:0] immediate = inst_buffer[15:0];
wire [31:0] sign_extend_immediate;
assign sign_extend_immediate = (immediate[15]==1'b1)?{16'hffff,immediate[15:0]}:{16'h0000,immediate[15:0]};
wire [31:0] zero_extend_immediate;
assign zero_extend_immediate = {16'h0000,immediate[15:0]};
reg taken;

//FSM parameter
reg [2:0]current_state,next_state;
localparam IDLE     = 3'd0;
localparam EXE      = 3'd1;
localparam WB       = 3'd2;
localparam MEM      = 3'd3;
localparam OUT      = 3'd4;

//define opcode and function field
localparam OP_R     = 6'd0;
localparam OP_andi  = 6'd1;
localparam OP_ori   = 6'd2;
localparam OP_addi  = 6'd3;
localparam OP_subi  = 6'd4;
localparam OP_lw    = 6'd5;
localparam OP_sw    = 6'd6;
localparam OP_beq   = 6'd7;
localparam OP_bnq   = 6'd8;

localparam funct_and    = 6'd0;
localparam funct_or     = 6'd1;
localparam funct_add    = 6'd2;
localparam funct_sub    = 6'd3;
localparam funct_slt    = 6'd4;
localparam funct_sll    = 6'd5;

//store the ALU result
reg signed [31:0] EXE_OUT;
integer i;

//------------------------------------------------------------------------
//   DESIGN
//------------------------------------------------------------------------

//------------------------------------------------------------------------
//  FSM
//------------------------------------------------------------------------
always @(posedge clk, negedge rst_n) begin
    if(!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

always @(*) begin
    case(current_state)
        IDLE:   if(in_valid)    next_state = EXE;
                else            next_state = IDLE;
        EXE:    if((opcode==OP_lw) || (opcode==OP_sw))
                    next_state = MEM;
                else                                    
                    next_state = WB;
        MEM:    next_state = WB;
        WB:     next_state = OUT;
        OUT:    next_state = IDLE;
        default: next_state = IDLE;
    endcase
end

//read instruction when in_valid is high
always @(posedge clk, negedge rst_n) begin
    if(!rst_n)
        inst_buffer <= 32'd0;
    //instruction is valid, read in instruction buffer
    else if(in_valid) inst_buffer <= inst;
    else inst_buffer <= inst_buffer;
end

//EXE
always @(*) begin
    case(opcode)
        //R-type opcode
        OP_R: begin
            case(funct)
                funct_and   : EXE_OUT = r[rs] & r[rt]; //add
                funct_or    : EXE_OUT = r[rs] | r[rt]; //or
                funct_add   : EXE_OUT = r[rs] + r[rt]; //add
                funct_sub   : EXE_OUT = r[rs] - r[rt]; //sub
                funct_slt   :begin                     //slt  
                    if(signed'(r[rs]) < signed'(r[rt]))
                        EXE_OUT = 32'd1;
                    else
                        EXE_OUT = 32'd0;
                end
                funct_sll   : EXE_OUT = r[rs] << shamt;  //sll
                default: EXE_OUT = 0;
            endcase
        end

        //I-type opcode
        OP_andi     : EXE_OUT = r[rs] & zero_extend_immediate; //andi
        OP_ori      : EXE_OUT = r[rs] | zero_extend_immediate; //ori
        OP_addi     : EXE_OUT = r[rs] + sign_extend_immediate; //addi
        OP_subi     : EXE_OUT = r[rs] - sign_extend_immediate; //subi
        OP_lw       : EXE_OUT = r[rs] + sign_extend_immediate; //lw
        OP_sw       : EXE_OUT = r[rs] + sign_extend_immediate; //sw
        OP_beq      : EXE_OUT = 32'd0; //beq -> other always block to exe
        OP_bnq      : EXE_OUT = 32'd0; //beq -> other always block to exe
        default: EXE_OUT = 0;
    endcase
end

//branch taken or not taken
always @(*) begin
    if(opcode==OP_beq)begin
        if(r[rs]==r[rt]) taken = 1'b1;
        else taken = 1'b0;
    end
    else if(opcode==OP_bnq)begin
        if(r[rs]!=r[rt]) taken = 1'b1;
        else taken = 1'b0;
    end
    else taken = 1'b0;
end

//calculate beq and bnq address
always @(posedge clk, negedge rst_n) begin
    if(!rst_n)begin
        inst_addr <= 32'd0;
    end
    else if(taken && next_state==WB)begin
        inst_addr <= inst_addr + 4 + (sign_extend_immediate<<2);
    end
    else if(!taken && next_state==WB)begin
        inst_addr <= inst_addr + 4;
    end
    else inst_addr <= inst_addr;
end

//MEM
always @(*) begin
    //load word
    if(opcode==OP_lw && current_state==MEM)begin
        mem_wen=1'b1;
        mem_addr=EXE_OUT;
    end
    //store word
    else if(opcode==OP_sw && current_state==MEM)begin
        mem_wen=0'b0;
        mem_addr=EXE_OUT;
        mem_din = r[rt];
    end
    else
        mem_wen = 1'b1;
end

//WB
always @(posedge clk or negedge rst_n) begin
    //initialize
    if (!rst_n) begin
        for(i=0;i<32;i=i+1)begin
            r[i] <= 32'd0;
        end
	end
    else if(current_state==WB)begin
        case(opcode)
            OP_R        : r[rd] <= EXE_OUT; //R-type write back
            OP_andi     : r[rt] <= EXE_OUT; //andi write back
            OP_ori      : r[rt] <= EXE_OUT; //ori write back
            OP_addi     : r[rt] <= EXE_OUT; //addi write back
            OP_subi     : r[rt] <= EXE_OUT; //subi write back
            OP_lw       : r[rt] <= mem_dout;//lw write back
        endcase
    end
end

//OUT
always @(posedge clk, negedge rst_n) begin
    if(!rst_n) out_valid <=0;
    else if(next_state==OUT) out_valid <=1;
    else out_valid <=0;
end

endmodule