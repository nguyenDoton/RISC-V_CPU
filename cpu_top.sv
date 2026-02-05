`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/17/2025 06:19:00 PM
// Design Name: 
// Module Name: cpu_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module basys3_top(
    input  logic       CLK100MHZ, // The physical W5 pin
    input  logic       btnC,      // The physical Reset Button
    input  logic [0:0] sw,        // Switch 0 (Speed Control)
    output logic [15:0] led       // The physical LEDs
    );

    // 1. Clock Divider (Slow down 100MHz to ~3Hz)
    logic [25:0] counter;
    logic        slow_clk;

    always_ff @(posedge CLK100MHZ) begin
        counter <= counter + 1;
    end

    // Switch 0 UP   = Fast Clock (Good for quick testing)
    // Switch 0 DOWN = Human Speed (So you can watch the binary count)
    assign slow_clk = counter[24];


    cpu_top cpu (
        .clk(slow_clk),    
        .rst(btnC),        
        .output_led(led)   
    );

endmodule

module cpu_top(
    input clk,
    input rst,
    output [15:0] output_led
    );
    
    //Instruction mem
// ==========================================
    //              INTERNAL WIRES
    // ==========================================
    
    // PC & Instruction Signals
    logic [31:0] pc, pc_next, pc_plus4, pc_target;
    logic [31:0] inst;
    
    // Register File Signals
    logic [31:0] rd_data1, rd_data2;
    logic [31:0] result; // The final data written back to RegFile
    
    // Immediate Generation
    logic [31:0] imm_ext;
    
    // ALU Signals
    logic [31:0] src_a;
    logic [31:0] src_b;
    logic [31:0] alu_result;
    logic        zero_flag;
    
    // Data Memory Signals
    logic [31:0] mem_read_data;
    
    // Control Unit Signals
    logic [2:0]  ctrl_imm;
    logic [3:0]  alu_op;
    logic [2:0]  mem_mode;
    logic        alu_src; 
    logic        wr_reg_en; 
    logic        wr_data_en; 
    logic        pc_ctrl;
    logic [1:0]  result_ctrl; // 2-bit Mux selector
    logic        auipc;
    // Unused/Debug signals
    logic        misalign_ignored; 

    // ==========================================
    //           1. FETCH STAGE
    // ==========================================
    
    assign pc_plus4 = pc + 4;
    assign pc_target = pc + imm_ext; // Standard Branch/JAL target
    
    // --- JALR Logic ---
    // If Opcode is JALR (11001), the target comes from ALU (rs1 + imm).
    // Otherwise, the target is the standard PC + Imm.
    logic [31:0] branch_jump_target;
    assign branch_jump_target = (inst[6:2] == 5'b11001) ? (alu_result & ~1) : pc_target;
    // --- Next PC Mux ---
    // If pc_ctrl is High (Branch Taken or Jump), go to target. Else PC+4.
    assign pc_next = (pc_ctrl) ? branch_jump_target : pc_plus4;

    program_counter pc_mod (
        .clk(clk),
        .rst(rst),
        .pc_next(pc_next),
        .pc(pc),
        .misalign_alert(misalign_ignored)
    );

    inst_mem imem (
        .pc(pc),
        .rst(rst),
        .inst(inst)
    );

    // ==========================================
    //           2. DECODE STAGE
    // ==========================================

    control_unit ctrl_unit (
        .inst(inst),
        .zero(zero_flag),
        .result(alu_result), // Connect LSB of ALU to Control Unit for BLT/BGE
        .ctrl(ctrl_imm),
        .alu_op(alu_op),
        .mem_mode(mem_mode),
        .alu_src(alu_src),
        .wr_reg_en(wr_reg_en),
        .wr_data_en(wr_data_en),
        .pc_ctrl(pc_ctrl),
        .result_ctrl(result_ctrl),
        .auipc(auipc)
    );

    reg_file rf (
        .clk(clk),
        .reg_addr1(inst[19:15]), // rs1
        .reg_addr2(inst[24:20]), // rs2
        .wr_reg_addr(inst[11:7]), // rd
        .wr_reg_en(wr_reg_en),
        .wr_data(result),        // Writeback data connects here
        .rd_data1(rd_data1),
        .rd_data2(rd_data2)
    );

    extendnator ext (
        .ctrl(ctrl_imm),
        .inst(inst),
        .extended_data(imm_ext)
    );

    // ==========================================
    //           3. EXECUTE STAGE
    // ==========================================

    // ALU Source B Mux: Select between Register 2 or Immediate
    assign src_b = (alu_src) ? imm_ext : rd_data2;
    assign src_a = (auipc)? pc : rd_data1;
    alu main_alu (
        .s1(src_a),
        .s2(src_b),
        .op(alu_op),
        .result(alu_result),
        .zero(zero_flag)
    );

    // ==========================================
    //           4. MEMORY STAGE
    // ==========================================

    data_mem dmem (
        .clk(clk),
        .wr_data_en(wr_data_en),
        .mem_mode(mem_mode),
        .addr(alu_result),   // Address comes from ALU
        .wr_data(rd_data2),  // Data to write comes from Reg2
        .rd_data(mem_read_data),
        .led_output(output_led)
    );

    // ==========================================
    //           5. WRITEBACK STAGE
    // ==========================================
    
    // The 3-Way Multiplexer for determining what goes into rd
    always_comb begin
        case (result_ctrl)
            2'b00: result = alu_result;    // Math / Logic Results
            2'b01: result = mem_read_data; // Load from Memory (LW, LB, etc.)
            2'b10: result = pc_plus4;      // Return Address (JAL, JALR)
            default: result = 32'b0;
        endcase
    end
    
    //assign output_led = result[15:0];
    
endmodule

module alu(
  input logic [31:0] s1,
  input logic [31:0] s2,
  input logic [3:0] op,
  output logic [31:0] result,
  output logic zero
  
);
 always_comb begin
 case (op)
   4'b0000: result  = s1 + s2; //ADD
   4'b0001: result  = s1 - s2; //SUB
   4'b0010: result  = s1 & s2; //AND
   4'b0011: result  = s1 | s2;  //OR
   4'b0100: result  = s1 ^ s2;  //XOR
   4'b0101: result  = s1 << s2[4:0]; // SLL
   4'b0110: result = s1 >> s2[4:0]; //SRL
   4'b0111: result = (s1 < s2)? 32'd1 : 32'd0; //USLT
   4'b1000: result = ($signed(s1) < $signed(s2))? 32'd1 : 32'd0; //SLT ( set less than)
   4'b1001: result = $signed(s1) >>> s2[4:0];//arithmetic shift right
   4'b1010: result = s2; // function for LUI
   default: result = 32'b0; 
   endcase
   end
   assign zero = (result == 32'b0);
endmodule

module control_unit(
   input logic [31:0] inst,
   input logic zero,
   input logic [31:0] result,
   output logic [2:0] ctrl, //imm ctrl
   output logic [3:0] alu_op,  //alu op 
   output logic [2:0] mem_mode,  // byte, half, word load mode
   output logic alu_src,  // 0-takes register data, 1- take immediate
   output logic wr_reg_en,  // register write enabled
   output logic wr_data_en, //memory write enabled
   output logic pc_ctrl,  //jump
   output logic auipc, //signal for auipc inst
   output logic [1:0] result_ctrl  //0-take alu output, 1-take memory value
);
  logic [6:0] opcode;
  logic func7;
  logic [2:0] func3;
  assign opcode = inst[6:0];
  assign func3 = inst[14:12];
  assign func7 = inst[30];
  always_comb begin
       wr_reg_en   = 0;
       wr_data_en  = 0;
       pc_ctrl     = 0;
       result_ctrl = 2'b00; 
       alu_src     = 0; 
       alu_op    = 4'b0000;
       mem_mode = func3; 
       auipc = 0;
       ctrl = 3'b000;
      case (opcode[6:2])
        5'b00000:  //Load from memory
        begin 
            wr_data_en = 0;  
            wr_reg_en = 1;
            pc_ctrl = 0;
            result_ctrl = 2'b01;
            alu_src = 1 ;
            alu_op = 4'b0000;
            mem_mode = func3;
            auipc = 0;
            ctrl = 3'b000;
        end
        5'b00100: //Math with immediate
        begin 
           wr_data_en = 0;
           alu_src = 1; //use extendnator data
           wr_reg_en= 1;
           result_ctrl = 2'b00;
           pc_ctrl =0;
           ctrl = 3'b000;
           
           case (func3) 
               3'b000: alu_op = 4'b0000; //addi
               3'b001: alu_op = 4'b0101; //slli
               3'b010:alu_op = 4'b1000;  //slti signed
               3'b011:alu_op = 4'b0111; //slti unsigned
               3'b100: alu_op = 4'b0100;  //xori
               3'b101: begin  //shift right 
                  if(func7) alu_op = 4'b1001; //arithmetic 
                  else alu_op = 4'b0110; //logical
               end   
               3'b110: alu_op = 4'b0011; //ori 
               3'b111: alu_op = 4'b0010; //andi
               default: alu_op = 4'b0000; // addi as default
           endcase
           end  
        5'b01000:  //Write to memory
        begin
           result_ctrl = 2'b00; //take result from alu
           wr_reg_en = 0;  //reg write disabled
           wr_data_en = 1; //write enabled
           alu_src = 1; //use immediate
           ctrl = 3'b001; //S-type 
        end 
        5'b01100: //Math with register
        begin 
         result_ctrl = 2'b00; //write back data from alu
         alu_src = 0; //use registers data
         wr_reg_en = 1; //write to reg enabled
         wr_data_en = 0; //write to mem disabled
         case (func3)
           3'b000: if(func7) alu_op = 4'b0001; //sub
                   else alu_op = 4'b0000; //add
           3'b001: alu_op = 4'b0101; //
           3'b010: alu_op = 4'b1000;
           3'b011: alu_op = 4'b0111;
           3'b100: alu_op = 4'b0100;
           3'b101: if (func7) alu_op = 4'b1001; //sla
                   else alu_op = 4'b0110;  //sll
           3'b110: alu_op = 4'b0011;
           3'b111: alu_op = 4'b0010;
         endcase
        end 
        5'b01101: //Load upper immediate
        begin
           wr_reg_en = 1;
           pc_ctrl =1'b0;
           result_ctrl = 0;
           wr_data_en = 0;
           alu_op = 4'b1010;
           alu_src = 1;
           ctrl = 3'b011;
        end  
        5'b11000: //Conditional jump
        case(func3)
        3'b000: //beq
        begin
           wr_reg_en  = 0;
           result_ctrl = 2'b00;
           alu_src = 0;
           ctrl = 3'b010; // B-type
           alu_op = 4'b0001;  //sub and check zero
           if(zero) pc_ctrl = 1;
        end
        3'b001: //bne
        begin
           wr_reg_en = 0;
           result_ctrl = 2'b00;
           alu_src = 0;
           ctrl = 3'b010; //B-type inst
           alu_op = 4'b0001; //sub
           if(!zero) pc_ctrl = 1;
        end
        3'b100: //blt
        begin
           wr_reg_en = 0;
           result_ctrl = 2'b00;
           alu_src = 0;
           ctrl = 3'b010; //B-type inst
           alu_op = 4'b1000; //slt signed
           if(result == 32'b1) pc_ctrl = 1;
        end
        
        3'b101: //bge
        begin
           wr_reg_en = 0;
           result_ctrl = 2'b00;
           alu_src = 0;
           ctrl = 3'b010; //B-type inst
           alu_op = 4'b1000; //slt signed
           if(result == 32'b0) pc_ctrl = 1;
        end
        3'b110: //blt unsigned
        begin
           wr_reg_en = 0;
           result_ctrl = 2'b00;
           alu_src = 0;
           ctrl = 3'b010; //B-type inst
           alu_op = 4'b0111; //sltu
           if(result == 32'b1) pc_ctrl = 1;
        end
        3'b111: //bge unsigned
        begin
           wr_reg_en = 0;
           result_ctrl = 2'b00;
           alu_src = 0;
           ctrl = 3'b010; //B-type inst
           alu_op = 4'b0111; //sltu
           if(result == 32'b0) pc_ctrl = 1;
        end
        default: 
        begin
           wr_reg_en  = 0;
           result_ctrl = 2'b00;
           alu_src = 0;
           ctrl = 3'b010; // B-type
           alu_op = 4'b0001;  //sub and check zero
           if(zero) pc_ctrl = 1;
        end
        endcase
        5'b11001: //Jump register jalr
        begin
           auipc = 0;
           ctrl = 3'b000;  //I-type inst
           pc_ctrl = 1;
           wr_reg_en = 1;
           alu_src = 1; //Calculate rs1 +Imm
           alu_op = 4'b0000; // Add rs1 +Imm
           result_ctrl = 2'b10; //result goes to PC
        end  
        5'b11011:  //Unconditional jump  jal
        begin
           ctrl = 3'b100; // J-type inst 
           wr_reg_en = 1;
           pc_ctrl =1;
           result_ctrl = 2'b10; //Result goes to PC
           alu_src = 1;
           alu_op = 4'b0000;
        end
        5'b00101: //Add upper immediate to PC
        begin
            wr_reg_en = 1;
            pc_ctrl = 0;
            result_ctrl = 2'b00;
            wr_data_en = 0;
            alu_src = 1; 
            auipc = 1;
            ctrl = 3'b011; // U-type inst
        end  
        endcase

  end
endmodule

module extendnator(
  input logic [2:0] ctrl,
  input logic [31:0] inst,
  output logic [31:0] extended_data
  );
  always_comb begin
    case (ctrl)
    3'b000: extended_data = {{20{inst[31]}}, inst[31:20]}; // I-type instruction
    3'b001: extended_data = {{20{inst[31]}}, inst[31:25],inst[11:7]};  //S-type instruction
    3'b010: extended_data = {{20{inst[31]}},inst[7],inst[30:25],inst[11:8],1'b0}; //B-type instruction
    3'b011: extended_data = {inst[31:12],12'b0}; // U-type instruction
    3'b100: extended_data = {{12{inst[31]}},inst[19:12],inst[20],inst[30:21],1'b0}; //J-type instruction
    
        default: extended_data = 32'b0;
  endcase
  end
endmodule 

module program_counter(
 input logic [31:0] pc_next,
 input logic clk,
 input logic rst,
 output logic [31:0] pc,
 output logic misalign_alert
);



always_ff @(posedge clk or posedge rst) begin
    if(rst) pc <= 32'b0;
    else pc <= pc_next;
   
end

assign misalign_alert = (pc_next[1:0] != 2'b00);

endmodule



module reg_file(
 input logic [4:0]  reg_addr1,
 input logic [4:0]  reg_addr2,
 input logic [4:0]  wr_reg_addr,
 input logic wr_reg_en,
 input logic [31:0] wr_data,
 input logic clk,
 output logic [31:0] rd_data1,
 output logic [31:0] rd_data2
 );
 
 logic [31:0] regs [0:31] ;
 
 always_ff @(posedge clk) begin
    //Write data
    if(wr_reg_en && wr_reg_addr != 5'b0) begin
       regs[wr_reg_addr] <= wr_data;
    end
 end
 //Read data
 assign rd_data1 = (reg_addr1 != 5'b0) ? regs[reg_addr1] : 32'b0;
 assign rd_data2 = (reg_addr2 != 5'b0) ? regs[reg_addr2] : 32'b0;
endmodule

module inst_mem(  
   input logic [31:0] pc,
   input logic rst,
   output logic [31:0] inst
);  //instruction memory

   
   logic [31:0] prog_mem [0:255];
   
   initial begin
       // This tells Vivado to load your hex code into the FPGA Block RAM
       $readmemh("program1.mem", prog_mem); 
   end
   
   always_comb 
   begin
        inst = prog_mem[pc[31:2]];
   end
 
endmodule

module data_mem(
   input logic [31:0] wr_data,
   input logic [31:0] addr,
   input logic clk,
   input logic [2:0] mem_mode,
   input logic wr_data_en,
   output logic [31:0] rd_data,
   output logic [15:0] led_output
);

   logic [31:0] data_memory [0:255];
   logic [15:0] mmio_led_reg;
   assign led_output = mmio_led_reg;
   
   
   always_ff@(posedge clk) begin
          //Write data
          if(wr_data_en) begin
          if (addr == 32'h0000_8000 ) begin
                mmio_led_reg <= wr_data[15:0];
          end
          else begin
          case (mem_mode) 
          3'b000: 
          case(addr[1:0])  //sb
          2'b00: data_memory[addr[31:2]][7:0] <= wr_data[7:0]; 
          2'b01: data_memory[addr[31:2]][15:8] <= wr_data[7:0];
          2'b10: data_memory[addr[31:2]][23:16] <= wr_data[7:0];
          2'b11: data_memory[addr[31:2]][31:24] <= wr_data[7:0];
          endcase
          
          
          3'b001: //sh
          case(addr[1])  
          1'b0: data_memory[addr[31:2]][15:0] <= wr_data[15:0]; 
          1'b1: data_memory[addr[31:2]][31:16] <= wr_data[15:0];
          endcase
          3'b010: data_memory[addr[31:2]] <= wr_data; //sw
          
          
          default: data_memory[addr[31:2]] <= wr_data;  //sw as defaullt
          endcase
          end
          end
          end
          
    logic [31:0] temp_data; 
//    assign temp_data = data_memory[addr[31:2]]; //Load data
    assign temp_data = (addr == 32'h0000_8000) ? {16'b0, mmio_led_reg} : data_memory[addr[31:2]];
    always_comb  begin     
       rd_data = 32'b0;      //Load data
       case(mem_mode)
          3'b000: //lb
          case(addr[1:0])
          2'b00: rd_data = {{24{temp_data[7]}},temp_data[7:0]};
          2'b01: rd_data = {{24{temp_data[15]}},temp_data[15:8]};
          2'b10: rd_data = {{24{temp_data[23]}},temp_data[23:16]};
          2'b11: rd_data = {{24{temp_data[31]}},temp_data[31:24]};
          endcase
          3'b001://lh
          case(addr[1])
          1'b0:  rd_data = {{16{temp_data[15]}}, temp_data[15:0]};
          1'b1:  rd_data = {{16{temp_data[31]}}, temp_data[31:16]};
          endcase
          3'b010: //lw
                 rd_data = temp_data;
          3'b100: //lbu
          case(addr[1:0])
          2'b00: rd_data = temp_data[7:0];
          2'b01: rd_data = temp_data[15:8];
          2'b10: rd_data = temp_data[23:16];
          2'b11: rd_data = temp_data[31:24];
          endcase
          3'b101: //lhu
          case(addr[1])
          1'b0:  rd_data = temp_data[15:0];
          1'b1:  rd_data = temp_data[31:16];
          endcase
          default: rd_data = temp_data;
       endcase
     end
endmodule
