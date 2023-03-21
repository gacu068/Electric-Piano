`define silence   32'd50000000

module lab8(
    clk,        // clock from crystal
    rst,        // BTNC: active high reset
    _play,      // SW0: Play/Pause
    _mute,      // SW1: Mute
    _slow,      // SW2: Slow
    _music,     // SW3: Music
    _mode,      // SW15: Mode
    _volUP,     // BTNU: Vol up
    _volDOWN,   // BTND: Vol down
    _higherOCT, // BTNR: Oct higher
    _lowerOCT,  // BTNL: Oct lower
    PS2_DATA,   // Keyboard I/O
    PS2_CLK,    // Keyboard I/O
    _led,       // LED: [15:13] octave & [4:0] volume
    audio_mclk, // master clock
    audio_lrck, // left-right clock
    audio_sck,  // serial clock
    audio_sdin, // serial audio data input
    DISPLAY,    // 7-seg
    DIGIT       // 7-seg
);

    
    // I/O declaration
    input clk; 
    input rst; 
    input _play, _mute, _slow, _music, _mode; 
    input _volUP, _volDOWN, _higherOCT, _lowerOCT; 
    inout PS2_DATA; 
	inout PS2_CLK; 
    output reg [15:0] _led; 
    output audio_mclk; 
    output audio_lrck; 
    output audio_sck; 
    output audio_sdin; 
    output reg [6:0] DISPLAY; 
    output reg [3:0] DIGIT; 

    //clkdiv15
    wire clkDiv15;
    clock_divider #(.n(15)) clock_15(.clk(clk), .clk_div(clkDiv15)); 

    wire clkDiv23;
    clock_divider #(.n(23)) clock_26(.clk(clk), .clk_div(clkDiv23)); 


    wire _volUP_debounced;
    wire _volDOWN_debounced;
    wire _higherOCT_debounced;
    wire _lowerOCT_debounced;

    debounce de1(_volUP_debounced,_volUP,clkDiv15);
    debounce de2(_volDOWN_debounced,_volDOWN,clkDiv15);
    debounce de3(_higherOCT_debounced,_higherOCT,clkDiv15);
    debounce de4(_lowerOCT_debounced,_lowerOCT,clkDiv15);

    wire _volUP_1pulse;
    wire _volDOWN_1pulse;
    wire _higherOCT_1pulse;
    wire _lowerOCT_1pulse;

    onepulse one1(_volUP_debounced,clkDiv15,_volUP_1pulse);
    onepulse one2(_volDOWN_debounced,clkDiv15,_volDOWN_1pulse);
    onepulse one3(_higherOCT_debounced,clkDiv15,_higherOCT_1pulse);
    onepulse one4(_lowerOCT_debounced,clkDiv15,_lowerOCT_1pulse);

    wire shift_down;
	wire [511:0] key_down;
	wire [8:0] last_change;
	wire been_ready;
    
    reg [2:0] volume;
    reg [1:0] octave;
    reg [2:0] volume_next;
    reg [1:0] octave_next;

    parameter Lower = 2'b00;
    parameter Normal = 2'b01;
    parameter Higher = 2'b10;

    parameter mid = 3'd3;

    wire [2:0] volume2;
    assign volume2 = (_mute == 1) ? 3'b000 : volume;

    //volume and octave control
    always @(posedge clkDiv15, posedge rst) begin
        if(rst)begin
            octave <= Normal;
        end else begin
            octave <= octave_next;
        end
    end

    always @(posedge clkDiv15, posedge rst) begin
        if(rst)begin
            volume <= mid;
        end else begin
            volume <= volume_next;
        end
    end

    always @(*) begin
        if(_volUP_1pulse)begin
            if(volume < 5)volume_next = volume + 1;
            else volume_next = volume;
        end else if(_volDOWN_1pulse)begin
            if(volume > 1)volume_next = volume - 1;
            else volume_next = 1;
        end else begin
            volume_next = volume;
        end
    end

    always @(*) begin
        if(_higherOCT_1pulse)begin
            if(octave < 2)octave_next = octave + 1;
            else octave_next = octave;
        end else if(_lowerOCT_1pulse)begin
            if(octave > 0)octave_next = octave - 1;
            else octave_next = octave;
        end else begin
            octave_next = octave;
        end
    end

    always @(*) begin
        case (octave)
            Lower:_led[15:13] = 3'b100;
            Normal:_led[15:13] = 3'b010;
            Higher:_led[15:13] = 3'b001;
            default:_led[15:13] = 3'b000;
        endcase
    end

    always @(*) begin
        case (volume2)
            3'd0:_led[4:0] = 5'b00000;
            3'd1:_led[4:0] = 5'b00001;
            3'd2:_led[4:0] = 5'b00011;
            3'd3:_led[4:0] = 5'b00111;
            3'd4:_led[4:0] = 5'b01111;
            3'd5:_led[4:0] = 5'b11111;
            default:_led[4:0] = 5'b11011;
        endcase
        
    end
    

    // Internal Signal
    wire [15:0] audio_in_left, audio_in_right;

    wire [11:0] ibeatNum;               // Beat counter
    wire [31:0] freqL, freqR;           // Raw frequency, produced by music module
    wire [21:0] freq_outL, freq_outR;  
    reg [21:0] freq_outL2, freq_outR2;  // Processed frequency, adapted to the clock rate of Basys3

    assign freq_outL = (_play == 0 && _mode == 1)? 1 : freq_outL2;
    assign freq_outR = (_play == 0 && _mode == 1)? 1 : freq_outR2;
    // clkDiv22
    wire clkDiv22;
    clock_divider #(.n(22)) clock_22(.clk(clk), .clk_div(clkDiv22));
    wire clkDiv21;
    clock_divider #(.n(21)) clock_21(.clk(clk), .clk_div(clkDiv21));
    
         // for keyboard and audio

    wire change_clk;
    assign change_clk = (_slow==1) ? clkDiv22 : clkDiv21;
    // Player Control
    // [in]  reset, clock, _play, _slow, _music, and _mode
    // [out] beat number
    player_control #(.LEN(512)) playerCtrl_00 ( 
        .clk(change_clk),
        .reset(rst),
        ._play(_play),
        ._slow(1'b0), 
        ._mode(_mode),
        .music(_music),
        .ibeat(ibeatNum)
    );

    // Music module
    // [in]  beat number and en
    // [out] left & right raw frequency
    music_example music_00 (
        .ibeatNum(ibeatNum),
        .en(1),
        .key_down(key_down),
        .last_change(last_change),
        .been_ready(been_ready),
        .mode(_mode),
        .music(_music),
        .toneL(freqL),
        .toneR(freqR)
    );

    // freq_outL, freq_outR
    // Note gen makes no sound, if freq_out = 50000000 / `silence = 1
    //assign freq_outL = 50000000 / freqL;
   // assign freq_outR = 50000000 / freqR;

    always @(*) begin
        case (octave)
            Lower:begin
                if(freqL == 50000000)freq_outL2 = 1;
                else freq_outL2 = (50000000 / freqL)*2;
                
                if(freqR == 50000000)freq_outR2 = 1;
                else freq_outR2 = (50000000 / freqR)*2;
                //freq_outL2 = (50000000 / freqL)*2;
                //freq_outR2 = (50000000 / freqR)*2;
            end
            Normal:begin
                freq_outL2 = 50000000 / freqL;
                freq_outR2 = 50000000 / freqR;
            end
            Higher: begin
                if(freqL == 50000000)freq_outL2 = 1;
                else freq_outL2 = (50000000 / freqL)/2;
                
                if(freqR == 50000000)freq_outR2 = 1;
                else freq_outR2 = (50000000 / freqR)/2;
            end
            default:begin
                freq_outL2 = 50000000 / freqL;
                freq_outR2 = 50000000 / freqR;
            end
        endcase
    end

    reg[3:0] value;
    reg[3:0] note;
    reg[3:0] notation;
    always @(*) begin
        if(_play == 0)begin
            note = 0;
            notation = 0;
        end else if(freqR % 131 == 0)begin
            note = 1;
            notation = 0;
        end else if(freqR % 147 == 0)begin
            note = 2;
            notation = 0;
        end else if(freqR % 165 == 0)begin
            note = 3;
            notation = 0;
        end else if(freqR % 174 == 0)begin
            note = 4;
            notation = 0;
        end else if(freqR % 196 == 0)begin
            note = 5;
            notation = 0;
        end else if(freqR % 220 == 0)begin
            note = 6;
            notation = 0;
        end else if(freqR % 247 == 0)begin
            note = 7;
            notation = 0;
        end else if(freqR % 466 == 0)begin
            note = 7;
            notation = 9;
        end else if(freqR % 622 == 0)begin
            note = 3;
            notation = 9;
        end else begin
            note = 0;
            notation = 0;
        end
        
    end
    //7-segment
    always @(posedge clkDiv15) begin
            case (DIGIT)//7'bGFE_DCBA
                4'b1110:begin
                    value = notation;
                    DIGIT = 4'b1101;
                end 
                4'b1101:begin
                    value = 0;
                    DIGIT = 4'b1011;
                end 
                4'b1011:begin
                    value = 0;
                    DIGIT = 4'b0111;
                end 
                4'b0111:begin
                    value = note;
                    DIGIT = 4'b1110;
                end

                default:begin
                    value = 10;
                    DIGIT = 4'b1110;
                end
            endcase        
    end

    always @(*) begin
        case (value)
            4'd0: DISPLAY = 7'b011_1111;
            4'd1: DISPLAY = 7'b100_0110;//C
            4'd2: DISPLAY = 7'b100_0000;//D
            4'd3: DISPLAY = 7'b000_0110;//E
            4'd4: DISPLAY = 7'b000_1110;//F
            4'd5: DISPLAY = 7'b000_0010;//G
            4'd6: DISPLAY = 7'b000_1000;//A
            4'd7: DISPLAY = 7'b000_0000;//B
            4'd8: DISPLAY = 7'b001_1100;//#
            4'd9: DISPLAY = 7'b000_0011;//b
            default: DISPLAY = 7'b111_1111;
        endcase

    end

    
    // Note generation
    // [in]  processed frequency
    // [out] audio wave signal (using square wave here)
    note_gen noteGen_00(
        .clk(clk), 
        .rst(rst), 
        .volume(volume2),
        .note_div_left(freq_outL), 
        .note_div_right(freq_outR), 
        .audio_left(audio_in_left),     // left sound audio
        .audio_right(audio_in_right)    // right sound audio
    );

    // Speaker controller
    speaker_control sc(
        .clk(clk), 
        .rst(rst), 
        .audio_in_left(audio_in_left),      // left channel audio data input
        .audio_in_right(audio_in_right),    // right channel audio data input
        .audio_mclk(audio_mclk),            // master clock
        .audio_lrck(audio_lrck),            // left-right clock
        .audio_sck(audio_sck),              // serial clock
        .audio_sdin(audio_sdin)             // serial audio data input
    );

    KeyboardDecoder key_de (
		.key_down(key_down),
		.last_change(last_change),
		.key_valid(been_ready),
		.PS2_DATA(PS2_DATA),
		.PS2_CLK(PS2_CLK),
		.rst(rst),
		.clk(clk)
	);

endmodule


module player_control (
	input clk, 
	input reset, 
	input _play, 
	input _slow, 
	input _mode,
	input music,
	output wire [11:0] ibeat
);
	parameter LEN = 4095;
	reg [11:0] ibeat1;
	reg [11:0] ibeat2;
    reg [11:0] next_ibeat1;
	reg [11:0] next_ibeat2;
	reg [11:0] next_ibeat;
	
	assign ibeat = (music) ? ibeat1 : ibeat2;

	always @(posedge clk, posedge reset) begin
		if (reset) begin
			ibeat1 <= 0;
			ibeat2 <= 0;
		end else begin
            if(_play == 1)begin
				if(music)begin
					ibeat1 <= next_ibeat1;
					ibeat2 <= 0;
				end else begin
					ibeat1 <= 0;
					ibeat2 <= next_ibeat2;
				end
			end else begin
				ibeat1 <= ibeat1;
				ibeat2 <= ibeat2;
			end
		end
	end

    always @(*) begin
        next_ibeat1 = (ibeat1 + 1 < LEN) ? (ibeat1 + 1) : 0;
		next_ibeat2 = (ibeat2 + 1 < LEN) ? (ibeat2 + 1) : 0;
    end
	
	/*
	always @(posedge clk, posedge reset) begin
		if (reset) begin
			ibeat <= 0;
		end else begin
            ibeat <= next_ibeat;
		end
	end

    always @* begin
        next_ibeat = (ibeat + 1 < LEN) ? (ibeat + 1) : LEN-1;
    end
	*/

endmodule


`define Mi  32'd330   
`define Do  32'd262
`define La  32'd440 
`define So  32'd392 
`define Fa  32'd348
`define Re  32'd294
`define So1 32'd196
`define Si  32'd494
`define Do2 32'd524
`define Do1 32'd131
`define So0 32'd98
`define Fa0 32'd87
`define Fa1 32'd174
`define La0 32'd100
`define Si0 32'd124
`define Do0 32'd66
`define Re2 32'd588
`define Mi2 32'd588
`define La1 32'd220
`define Si1 32'd247
`define Mi0 32'd83
`define Re1 32'd147
`define Re0 32'd74
`define Mi1 32'd165

`define Mi2_down  32'd622   
`define Si2_down  32'd466   

`define Mi1_down  32'd155   
`define Si0_down  32'd117   

`define sil   32'd50000000 // slience

module music_example (
	input [11:0] ibeatNum,
	input en,
    input [511:0] key_down,
	input [8:0] last_change,
	input been_ready,
    input mode,
    input music,
	output reg [31:0] toneL,
    output reg [31:0] toneR
);

    always @* begin
        if(mode == 1) begin
            if(music)begin
                case(ibeatNum)
                    12'd0: toneR = `sil;    12'd1: toneR = `sil;    
                    12'd2: toneR = `sil;    12'd3: toneR = `sil;
                    12'd4: toneR = `sil;    12'd5: toneR = `sil;
                    12'd6: toneR = `sil;    12'd7: toneR = `sil;
                    12'd8: toneR = `sil;    12'd9: toneR = `sil;
                    12'd10: toneR = `sil;    12'd11: toneR = `sil;
                    12'd12: toneR = `sil;    12'd13: toneR = `sil;
                    12'd14: toneR = `sil;    12'd15: toneR = `sil;

                    12'd16: toneR = `Mi;    12'd17: toneR = `Mi;
                    12'd18: toneR = `Mi;    12'd19: toneR = `Mi;
                    12'd20: toneR = `Mi;    12'd21: toneR = `Mi;    
                    12'd22: toneR = `Mi;    12'd23: toneR = `Mi;

                    12'd24: toneR = `Mi;    12'd25: toneR = `Mi;
                    12'd26: toneR = `sil;    12'd27: toneR = `Mi;
                    12'd28: toneR = `Mi;    12'd29: toneR = `Mi;
                    12'd30: toneR = `Mi;    12'd31: toneR = `sil;

                    12'd32: toneR = `Mi;    12'd33: toneR = `Mi;
                    12'd34: toneR = `Mi;    12'd35: toneR = `Mi;    
                    12'd36: toneR = `Mi;    12'd37: toneR = `Mi;
                    12'd38: toneR = `Mi;    12'd39: toneR = `Mi;

                    12'd40: toneR = `Mi;    12'd41: toneR = `Mi;
                    12'd42: toneR = `sil;    12'd43: toneR = `Mi;
                    12'd44: toneR = `Mi;    12'd45: toneR = `Mi;
                    12'd46: toneR = `Mi;    12'd47: toneR = `sil;

                    12'd48: toneR = `Do;    12'd49: toneR = `Do;
                    12'd50: toneR = `Do;    12'd51: toneR = `Do;
                    12'd52: toneR = `Do;    12'd53: toneR = `Do;    
                    12'd54: toneR = `Do;    12'd55: toneR = `Do;
                    12'd56: toneR = `Do;    12'd57: toneR = `Do;
                    12'd58: toneR = `Do;    12'd59: toneR = `Do;
                    12'd60: toneR = `Do;    12'd61: toneR = `Do;
                    12'd62: toneR = `Do;    12'd63: toneR = `Do;

                    12'd64: toneR = `Mi;    12'd65: toneR = `Mi;
                    12'd66: toneR = `Mi;    12'd67: toneR = `Mi;    
                    12'd68: toneR = `Mi;    12'd69: toneR = `Mi;
                    12'd70: toneR = `Mi;    12'd71: toneR = `Mi;
                    12'd72: toneR = `Mi;    12'd73: toneR = `Mi;
                    12'd74: toneR = `Mi;    12'd75: toneR = `Mi;
                    12'd76: toneR = `Mi;    12'd77: toneR = `Mi;
                    12'd78: toneR = `Mi;    12'd79: toneR = `Mi;

                    12'd80: toneR = `La;    12'd81: toneR = `La;
                    12'd82: toneR = `La;    12'd83: toneR = `La;
                    12'd84: toneR = `La;    12'd85: toneR = `La;
                    12'd86: toneR = `La;    12'd87: toneR = `La;
                    12'd88: toneR = `La;    12'd89: toneR = `La;
                    12'd90: toneR = `La;    12'd91: toneR = `La;
                    12'd92: toneR = `La;    12'd93: toneR = `La;
                    12'd94: toneR = `La;    12'd95: toneR = `La;

                    12'd96: toneR = `So;    12'd97: toneR = `So;
                    12'd98: toneR = `So;    12'd99: toneR = `So;
                    12'd100: toneR = `So;    12'd101: toneR = `So;
                    12'd102: toneR = `So;    12'd103: toneR = `So;
                    12'd104: toneR = `So;    12'd105: toneR = `So;
                    12'd106: toneR = `So;    12'd107: toneR = `So;
                    12'd108: toneR = `So;    12'd109: toneR = `So;
                    12'd110: toneR = `So;    12'd111: toneR = `So;

                    12'd112: toneR = `So;    12'd113: toneR = `So;
                    12'd114: toneR = `So;    12'd115: toneR = `So;
                    12'd116: toneR = `So;    12'd117: toneR = `So;
                    12'd118: toneR = `So;    12'd119: toneR = `So;
                    12'd120: toneR = `So;    12'd121: toneR = `So;
                    12'd122: toneR = `So;    12'd123: toneR = `So;
                    12'd124: toneR = `So;    12'd125: toneR = `So;
                    12'd126: toneR = `So;    12'd127: toneR = `So;

                    12'd128: toneR = `sil;    12'd129: toneR = `sil;
                    12'd130: toneR = `sil;    12'd131: toneR = `sil;    
                    12'd132: toneR = `sil;    12'd133: toneR = `sil;
                    12'd134: toneR = `sil;    12'd135: toneR = `sil;
                    12'd136: toneR = `Fa;    12'd137: toneR = `Fa;
                    12'd138: toneR = `Fa;    12'd139: toneR = `Fa;
                    12'd140: toneR = `Fa;    12'd141: toneR = `Fa;
                    12'd142: toneR = `Fa;    12'd143: toneR = `Fa;

                    12'd144: toneR = `Fa;    12'd145: toneR = `Fa;
                    12'd146: toneR = `Fa;    12'd147: toneR = `Fa;
                    12'd148: toneR = `Fa;    12'd149: toneR = `Fa;
                    12'd150: toneR = `Fa;    12'd151: toneR = `Fa;
                    12'd152: toneR = `Fa;    12'd153: toneR = `Fa;
                    12'd154: toneR = `Fa;    12'd155: toneR = `Fa;    
                    12'd156: toneR = `Fa;    12'd157: toneR = `Fa;
                    12'd158: toneR = `Fa;    12'd159: toneR = `sil;

                    12'd160: toneR = `Fa;    12'd161: toneR = `Fa;
                    12'd162: toneR = `Fa;    12'd163: toneR = `Fa;
                    12'd164: toneR = `Fa;    12'd165: toneR = `Fa;
                    12'd166: toneR = `Fa;    12'd167: toneR = `Fa;
                    12'd168: toneR = `Fa;    12'd169: toneR = `Fa;
                    12'd170: toneR = `Fa;    12'd171: toneR = `Fa;
                    12'd172: toneR = `Fa;    12'd173: toneR = `Fa;
                    12'd174: toneR = `Fa;    12'd175: toneR = `Fa;

                    12'd176: toneR = `Re;    12'd177: toneR = `Re;    
                    12'd178: toneR = `Re;    12'd179: toneR = `Re;
                    12'd180: toneR = `Re;    12'd181: toneR = `Re;
                    12'd182: toneR = `Re;    12'd183: toneR = `Re;
                    12'd184: toneR = `Re;    12'd185: toneR = `Re;
                    12'd186: toneR = `Re;    12'd187: toneR = `Re;
                    12'd188: toneR = `Re;    12'd189: toneR = `Re;
                    12'd190: toneR = `Re;    12'd191: toneR = `Re;

                    12'd192: toneR = `Do;    12'd193: toneR = `Do;
                    12'd194: toneR = `Do;    12'd195: toneR = `Do;
                    12'd196: toneR = `Do;    12'd197: toneR = `Do;
                    12'd198: toneR = `Do;    12'd199: toneR = `Do;
                    12'd200: toneR = `Do;    12'd201: toneR = `Do;    
                    12'd202: toneR = `Do;    12'd203: toneR = `Do;
                    12'd204: toneR = `Do;    12'd205: toneR = `Do;
                    12'd206: toneR = `Do;    12'd207: toneR = `Do;

                    12'd208: toneR = `Mi;    12'd209: toneR = `Mi;
                    12'd210: toneR = `Mi;    12'd211: toneR = `Mi;
                    12'd212: toneR = `Mi;    12'd213: toneR = `Mi;
                    12'd214: toneR = `Mi;    12'd215: toneR = `Mi;
                    12'd216: toneR = `Mi;    12'd217: toneR = `Mi;
                    12'd218: toneR = `Mi;    12'd219: toneR = `Mi;
                    12'd220: toneR = `Mi;    12'd221: toneR = `Mi;
                    12'd222: toneR = `Mi;    12'd223: toneR = `Mi; 

                    12'd224: toneR = `So1;    12'd225: toneR = `So1;
                    12'd226: toneR = `So1;    12'd227: toneR = `So1;
                    12'd228: toneR = `So1;    12'd229: toneR = `So1;
                    12'd230: toneR = `So1;    12'd231: toneR = `So1;
                    12'd232: toneR = `So1;    12'd233: toneR = `So1;
                    12'd234: toneR = `So1;    12'd235: toneR = `So1;
                    12'd236: toneR = `So1;    12'd237: toneR = `So1;
                    12'd238: toneR = `So1;    12'd239: toneR = `So1;    
                    12'd240: toneR = `So1;    12'd241: toneR = `So1;
                    12'd242: toneR = `So1;    12'd243: toneR = `So1;
                    12'd244: toneR = `So1;    12'd245: toneR = `So1;
                    12'd246: toneR = `So1;    12'd247: toneR = `So1;
                    12'd248: toneR = `So1;    12'd249: toneR = `So1;
                    12'd250: toneR = `So1;    12'd251: toneR = `So1;    
                    12'd252: toneR = `So1;    12'd253: toneR = `So1;
                    12'd254: toneR = `So1;    12'd255: toneR = `So1;

                    12'd256: toneR = `sil;    12'd257: toneR = `sil;
                    12'd258: toneR = `sil;    12'd259: toneR = `sil;
                    12'd260: toneR = `sil;    12'd261: toneR = `sil;
                    12'd262: toneR = `sil;    12'd263: toneR = `sil;
                    12'd264: toneR = `sil;    12'd265: toneR = `sil;
                    12'd266: toneR = `sil;    12'd267: toneR = `sil;
                    12'd268: toneR = `sil;    12'd269: toneR = `sil;
                    12'd270: toneR = `sil;    12'd271: toneR = `sil;

                    12'd272: toneR = `Mi;    12'd273: toneR = `Mi;
                    12'd274: toneR = `Mi;    12'd275: toneR = `Mi;
                    12'd276: toneR = `Mi;    12'd277: toneR = `Mi;
                    12'd278: toneR = `Mi;    12'd279: toneR = `Mi;
                    12'd280: toneR = `Mi;    12'd281: toneR = `Mi;
                    12'd282: toneR = `Mi;    12'd283: toneR = `Mi;
                    12'd284: toneR = `Mi;    12'd285: toneR = `Mi;
                    12'd286: toneR = `Mi;    12'd287: toneR = `sil;

                    12'd288: toneR = `Mi;    12'd289: toneR = `Mi;    
                    12'd290: toneR = `Mi;    12'd291: toneR = `Mi;
                    12'd292: toneR = `Mi;    12'd293: toneR = `Mi;
                    12'd294: toneR = `Mi;    12'd295: toneR = `Mi;
                    12'd296: toneR = `Mi;    12'd297: toneR = `Mi;
                    12'd298: toneR = `Mi;    12'd299: toneR = `sil;
                    12'd300: toneR = `Mi;    12'd301: toneR = `Mi;
                    12'd302: toneR = `Mi;    12'd303: toneR = `Mi;

                    12'd304: toneR = `Do;    12'd305: toneR = `Do;
                    12'd306: toneR = `Do;    12'd307: toneR = `Do;    
                    12'd308: toneR = `Do;    12'd309: toneR = `Do;
                    12'd310: toneR = `Do;    12'd311: toneR = `Do;
                    12'd312: toneR = `Do;    12'd313: toneR = `Do;
                    12'd314: toneR = `Do;    12'd315: toneR = `Do;
                    12'd316: toneR = `Do;    12'd317: toneR = `Do;
                    12'd318: toneR = `Do;    12'd319: toneR = `Do;

                    12'd320: toneR = `Mi;    12'd321: toneR = `Mi;
                    12'd322: toneR = `Mi;    12'd323: toneR = `Mi;
                    12'd324: toneR = `Mi;    12'd325: toneR = `Mi;
                    12'd326: toneR = `Mi;    12'd327: toneR = `Mi;
                    12'd328: toneR = `Mi;    12'd329: toneR = `Mi;    
                    12'd330: toneR = `Mi;    12'd331: toneR = `Mi;
                    12'd332: toneR = `Mi;    12'd333: toneR = `Mi;
                    12'd334: toneR = `Mi;    12'd335: toneR = `Mi;

                    12'd336: toneR = `La;    12'd337: toneR = `La;
                    12'd338: toneR = `La;    12'd339: toneR = `La;
                    12'd340: toneR = `La;    12'd341: toneR = `La;
                    12'd342: toneR = `La;    12'd343: toneR = `La;
                    12'd344: toneR = `La;    12'd345: toneR = `La;
                    12'd346: toneR = `La;    12'd347: toneR = `La;
                    12'd348: toneR = `La;    12'd349: toneR = `La;
                    12'd350: toneR = `La;    12'd351: toneR = `La;    

                    12'd352: toneR = `So;    12'd353: toneR = `So;
                    12'd354: toneR = `So;    12'd355: toneR = `So;
                    12'd356: toneR = `So;    12'd357: toneR = `So;
                    12'd358: toneR = `So;    12'd359: toneR = `So;
                    12'd360: toneR = `So;    12'd361: toneR = `So;
                    12'd362: toneR = `So;    12'd363: toneR = `So;
                    12'd364: toneR = `So;    12'd365: toneR = `So;
                    12'd366: toneR = `So;    12'd367: toneR = `So;

                    12'd368: toneR = `So;    12'd369: toneR = `So;    
                    12'd370: toneR = `So;    12'd371: toneR = `So;
                    12'd372: toneR = `So;    12'd373: toneR = `So;
                    12'd374: toneR = `So;    12'd375: toneR = `So;
                    12'd376: toneR = `So;    12'd377: toneR = `So;
                    12'd378: toneR = `So;    12'd379: toneR = `So;
                    12'd380: toneR = `So;    12'd381: toneR = `So;
                    12'd382: toneR = `So;    12'd383: toneR = `So;

                    12'd384: toneR = `sil;    12'd385: toneR = `sil;
                    12'd386: toneR = `sil;    12'd387: toneR = `sil;
                    12'd388: toneR = `sil;    12'd389: toneR = `sil;
                    12'd390: toneR = `sil;    12'd391: toneR = `sil;
                    12'd392: toneR = `sil;    12'd393: toneR = `sil;    
                    12'd394: toneR = `sil;    12'd395: toneR = `sil;
                    12'd396: toneR = `sil;    12'd397: toneR = `sil;
                    12'd398: toneR = `sil;    12'd399: toneR = `sil;

                    12'd400: toneR = `Fa;    12'd401: toneR = `Fa;
                    12'd402: toneR = `Fa;    12'd403: toneR = `Fa;
                    12'd404: toneR = `Fa;    12'd405: toneR = `Fa;
                    12'd406: toneR = `Fa;    12'd407: toneR = `Fa;
                    12'd408: toneR = `Fa;    12'd409: toneR = `Fa;    
                    12'd410: toneR = `Fa;    12'd411: toneR = `sil;
                    12'd412: toneR = `Fa;    12'd413: toneR = `Fa;
                    12'd414: toneR = `Fa;    12'd415: toneR = `Fa;

                    12'd416: toneR = `So;    12'd417: toneR = `So;
                    12'd418: toneR = `So;    12'd419: toneR = `So;
                    12'd420: toneR = `So;    12'd421: toneR = `So;
                    12'd422: toneR = `So;    12'd423: toneR = `So;
                    12'd424: toneR = `So;    12'd425: toneR = `So;
                    12'd426: toneR = `So;    12'd427: toneR = `So;
                    12'd428: toneR = `So;    12'd429: toneR = `So;    
                    12'd430: toneR = `So;    12'd431: toneR = `So;

                    12'd432: toneR = `Si;    12'd433: toneR = `Si;
                    12'd434: toneR = `Si;    12'd435: toneR = `Si;
                    12'd436: toneR = `Si;    12'd437: toneR = `Si;
                    12'd438: toneR = `Si;    12'd439: toneR = `Si;
                    12'd440: toneR = `Si;    12'd441: toneR = `Si;
                    12'd442: toneR = `Si;    12'd443: toneR = `Si;
                    12'd444: toneR = `Si;    12'd445: toneR = `Si;
                    12'd446: toneR = `Si;    12'd447: toneR = `Si;

                    12'd448: toneR = `Do2;    12'd449: toneR = `Do2;    
                    12'd450: toneR = `Do2;    12'd451: toneR = `Do2;
                    12'd452: toneR = `Do2;    12'd453: toneR = `Do2;
                    12'd454: toneR = `Do2;    12'd455: toneR = `Do2;
                    12'd456: toneR = `Do2;    12'd457: toneR = `Do2;
                    12'd458: toneR = `Do2;    12'd459: toneR = `Do2;
                    12'd460: toneR = `Do2;    12'd461: toneR = `Do2;
                    12'd462: toneR = `Do2;    12'd463: toneR = `Do2;

                    12'd464: toneR = `Do2;    12'd465: toneR = `Do2;
                    12'd466: toneR = `Do2;    12'd467: toneR = `Do2;
                    12'd468: toneR = `Do2;    12'd469: toneR = `Do2;
                    12'd470: toneR = `Do2;    12'd471: toneR = `Do2;
                    12'd472: toneR = `Do2;    12'd473: toneR = `Do2;    
                    12'd474: toneR = `Do2;    12'd475: toneR = `Do2;
                    12'd476: toneR = `Do2;    12'd477: toneR = `Do2;
                    12'd478: toneR = `Do2;    12'd479: toneR = `Do2;

                    12'd480: toneR = `Do2;    12'd481: toneR = `Do2;
                    12'd482: toneR = `Do2;    12'd483: toneR = `Do2;
                    12'd484: toneR = `Do2;    12'd485: toneR = `Do2;
                    12'd486: toneR = `Do2;    12'd487: toneR = `Do2;
                    12'd488: toneR = `Do2;    12'd489: toneR = `Do2;
                    12'd490: toneR = `Do2;    12'd491: toneR = `Do2;
                    12'd492: toneR = `Do2;    12'd493: toneR = `Do2;
                    12'd494: toneR = `Do2;    12'd495: toneR = `Do2;

                    12'd496: toneR = `Do2;    12'd497: toneR = `Do2;    
                    12'd498: toneR = `Do2;    12'd499: toneR = `Do2;
                    12'd500: toneR = `Do2;    12'd501: toneR = `Do2;
                    12'd502: toneR = `Do2;    12'd503: toneR = `Do2;
                    12'd504: toneR = `Do2;    12'd505: toneR = `Do2;
                    12'd506: toneR = `Do2;    12'd507: toneR = `Do2;
                    12'd508: toneR = `Do2;    12'd509: toneR = `Do2;
                    12'd510: toneR = `Do2;    12'd511: toneR = `Do2;
                    default: toneR = `sil;
                endcase
            
            end else begin
                case(ibeatNum)
                    12'd0: toneR = `sil;    12'd1: toneR = `sil;    
                    12'd2: toneR = `sil;    12'd3: toneR = `sil;
                    12'd4: toneR = `sil;    12'd5: toneR = `sil;
                    12'd6: toneR = `sil;    12'd7: toneR = `sil;
                    12'd8: toneR = `sil;    12'd9: toneR = `sil;
                    12'd10: toneR = `sil;    12'd11: toneR = `sil;
                    12'd12: toneR = `sil;    12'd13: toneR = `sil;
                    12'd14: toneR = `sil;    12'd15: toneR = `sil;

                    12'd16: toneR = `Re2;    12'd17: toneR = `Re2;
                    12'd18: toneR = `Re2;    12'd19: toneR = `Re2;
                    12'd20: toneR = `Re2;    12'd21: toneR = `Re2;
                    12'd22: toneR = `Re2;    12'd23: toneR = `Re2;    
                    12'd24: toneR = `Re2;    12'd25: toneR = `Re2;
                    12'd26: toneR = `Re2;    12'd27: toneR = `Re2;
                    12'd28: toneR = `Re2;    12'd29: toneR = `Re2;
                    12'd30: toneR = `Re2;    12'd31: toneR = `Re2;

                    12'd32: toneR = `Mi2_down;    12'd33: toneR = `Mi2_down;    
                    12'd34: toneR = `Mi2_down;    12'd35: toneR = `Mi2_down;    
                    12'd36: toneR = `Mi2_down;    12'd37: toneR = `Mi2_down;    
                    12'd38: toneR = `Mi2_down;    12'd39: toneR = `Mi2_down;
                    12'd40: toneR = `Re2;    12'd41: toneR = `Re2;
                    12'd42: toneR = `Re2;    12'd43: toneR = `Re2;    
                    12'd44: toneR = `Re2;    12'd45: toneR = `Re2;
                    12'd46: toneR = `Re2;    12'd47: toneR = `Re2;

                    12'd48: toneR = `Do2;    12'd49: toneR = `Do2;
                    12'd50: toneR = `Do2;    12'd51: toneR = `Do2;    
                    12'd52: toneR = `Do2;    12'd53: toneR = `Do2;
                    12'd54: toneR = `Do2;    12'd55: toneR = `Do2;
                    12'd56: toneR = `Re2;    12'd57: toneR = `Re2;
                    12'd58: toneR = `Re2;    12'd59: toneR = `Re2;    
                    12'd60: toneR = `Re2;    12'd61: toneR = `Re2;
                    12'd62: toneR = `Re2;    12'd63: toneR = `Re2;

                    12'd64: toneR = `So;    12'd65: toneR = `So;
                    12'd66: toneR = `So;    12'd67: toneR = `So;    
                    12'd68: toneR = `So;    12'd69: toneR = `So;
                    12'd70: toneR = `So;    12'd71: toneR = `So;
                    12'd72: toneR = `So;    12'd73: toneR = `So;
                    12'd74: toneR = `So;    12'd75: toneR = `So;
                    12'd76: toneR = `So;    12'd77: toneR = `So;    
                    12'd78: toneR = `So;    12'd79: toneR = `So;

                    12'd80: toneR = `Do2;    12'd81: toneR = `Do2;
                    12'd82: toneR = `Do2;    12'd83: toneR = `Do2;    
                    12'd84: toneR = `Do2;    12'd85: toneR = `Do2;
                    12'd86: toneR = `Do2;    12'd87: toneR = `Do2;
                    12'd88: toneR = `Si2_down;    12'd89: toneR = `Si2_down;
                    12'd90: toneR = `Si2_down;    12'd91: toneR = `Si2_down;
                    12'd92: toneR = `Si2_down;    12'd93: toneR = `Si2_down;
                    12'd94: toneR = `Si2_down;    12'd95: toneR = `Si2_down;    

                    12'd96: toneR = `Do2;    12'd97: toneR = `Do2;
                    12'd98: toneR = `Do2;    12'd99: toneR = `Do2;
                    12'd100: toneR = `Do2;    12'd101: toneR = `Do2;
                    12'd102: toneR = `Do2;    12'd103: toneR = `Do2;
                    12'd104: toneR = `Do2;    12'd105: toneR = `Do2;
                    12'd106: toneR = `Do2;    12'd107: toneR = `Do2;
                    12'd108: toneR = `Do2;    12'd109: toneR = `Do2;    
                    12'd110: toneR = `Do2;    12'd111: toneR = `Do2;

                    12'd112: toneR = `Si2_down;    12'd113: toneR = `Si2_down;
                    12'd114: toneR = `Si2_down;    12'd115: toneR = `Si2_down;
                    12'd116: toneR = `Si2_down;    12'd117: toneR = `Si2_down;
                    12'd118: toneR = `Si2_down;    12'd119: toneR = `Si2_down;
                    12'd120: toneR = `Si2_down;    12'd121: toneR = `Si2_down;
                    12'd122: toneR = `Si2_down;    12'd123: toneR = `Si2_down;
                    12'd124: toneR = `Si2_down;    12'd125: toneR = `Si2_down;    
                    12'd126: toneR = `Si2_down;    12'd127: toneR = `Si2_down;

                    12'd128: toneR = `Do2;    12'd129: toneR = `Do2;
                    12'd130: toneR = `Do2;    12'd131: toneR = `Do2;
                    12'd132: toneR = `Do2;    12'd133: toneR = `Do2;
                    12'd134: toneR = `Do2;    12'd135: toneR = `Do2;
                    12'd136: toneR = `Do2;    12'd137: toneR = `Do2;
                    12'd138: toneR = `Do2;    12'd139: toneR = `Do2;
                    12'd140: toneR = `Do2;    12'd141: toneR = `Do2;
                    12'd142: toneR = `Do2;    12'd143: toneR = `sil;    

                    12'd144: toneR = `Do2;    12'd145: toneR = `Do2;
                    12'd146: toneR = `Do2;    12'd147: toneR = `Do2;
                    12'd148: toneR = `Do2;    12'd149: toneR = `Do2;
                    12'd150: toneR = `Do2;    12'd151: toneR = `sil;
                    12'd152: toneR = `Do2;    12'd153: toneR = `Do2;
                    12'd154: toneR = `Do2;    12'd155: toneR = `Do2;    
                    12'd156: toneR = `Do2;    12'd157: toneR = `Do2;
                    12'd158: toneR = `Do2;    12'd159: toneR = `Do2;

                    12'd160: toneR = `Re2;    12'd161: toneR = `Re2;
                    12'd162: toneR = `Re2;    12'd163: toneR = `Re2;
                    12'd164: toneR = `Re2;    12'd165: toneR = `Re2;
                    12'd166: toneR = `Re2;    12'd167: toneR = `Re2;
                    12'd168: toneR = `Do2;    12'd169: toneR = `Do2;    
                    12'd170: toneR = `Do2;    12'd171: toneR = `Do2;
                    12'd172: toneR = `Do2;    12'd173: toneR = `Do2;
                    12'd174: toneR = `Do2;    12'd175: toneR = `Do2;

                    12'd176: toneR = `Si2_down;    12'd177: toneR = `Si2_down;
                    12'd178: toneR = `Si2_down;    12'd179: toneR = `Si2_down;
                    12'd180: toneR = `Si2_down;    12'd181: toneR = `Si2_down;
                    12'd182: toneR = `Si2_down;    12'd183: toneR = `Si2_down;
                    12'd184: toneR = `Do2;    12'd185: toneR = `Do2;
                    12'd186: toneR = `Do2;    12'd187: toneR = `Do2;
                    12'd188: toneR = `Do2;    12'd189: toneR = `Do2;
                    12'd190: toneR = `Do2;    12'd191: toneR = `Do2;    

                    12'd192: toneR = `Re2;    12'd193: toneR = `Re2;
                    12'd194: toneR = `Re2;    12'd195: toneR = `Re2;
                    12'd196: toneR = `Re2;    12'd197: toneR = `Re2;
                    12'd198: toneR = `Re2;    12'd199: toneR = `Re2;
                    12'd200: toneR = `Re2;    12'd201: toneR = `Re2;
                    12'd202: toneR = `Re2;    12'd203: toneR = `Re2;
                    12'd204: toneR = `Re2;    12'd205: toneR = `Re2;
                    12'd206: toneR = `Re2;    12'd207: toneR = `Re2;

                    12'd208: toneR = `Si2_down;    12'd209: toneR = `Si2_down;
                    12'd210: toneR = `Si2_down;    12'd211: toneR = `Si2_down;    
                    12'd212: toneR = `Si2_down;    12'd213: toneR = `Si2_down;
                    12'd214: toneR = `Si2_down;    12'd215: toneR = `Si2_down;
                    12'd216: toneR = `So;    12'd217: toneR = `So;
                    12'd218: toneR = `So;    12'd219: toneR = `So;
                    12'd220: toneR = `So;    12'd221: toneR = `So;
                    12'd222: toneR = `So;    12'd223: toneR = `So;

                    12'd224: toneR = `Si2_down;    12'd225: toneR = `Si2_down;
                    12'd226: toneR = `Si2_down;    12'd227: toneR = `Si2_down;    
                    12'd228: toneR = `Si2_down;    12'd229: toneR = `Si2_down;
                    12'd230: toneR = `Si2_down;    12'd231: toneR = `Si2_down;
                    12'd232: toneR = `Si2_down;    12'd233: toneR = `Si2_down;
                    12'd234: toneR = `Si2_down;    12'd235: toneR = `Si2_down;
                    12'd236: toneR = `Si2_down;    12'd237: toneR = `Si2_down;
                    12'd238: toneR = `Si2_down;    12'd239: toneR = `sil;

                    12'd240: toneR = `Si2_down;    12'd241: toneR = `Si2_down;
                    12'd242: toneR = `Si2_down;    12'd243: toneR = `Si2_down;
                    12'd244: toneR = `Si2_down;    12'd245: toneR = `Si2_down;
                    12'd246: toneR = `Si2_down;    12'd247: toneR = `Si2_down;    
                    12'd248: toneR = `Si2_down;    12'd249: toneR = `Si2_down;
                    12'd250: toneR = `Si2_down;    12'd251: toneR = `Si2_down;
                    12'd252: toneR = `Si2_down;    12'd253: toneR = `Si2_down;
                    12'd254: toneR = `Si2_down;    12'd255: toneR = `Si2_down;

                    12'd256: toneR = `So;    12'd257: toneR = `So;
                    12'd258: toneR = `So;    12'd259: toneR = `So;
                    12'd260: toneR = `So;    12'd261: toneR = `So;
                    12'd262: toneR = `So;    12'd263: toneR = `So;
                    12'd264: toneR = `So;    12'd265: toneR = `So;    
                    12'd266: toneR = `So;    12'd267: toneR = `So;
                    12'd268: toneR = `So;    12'd269: toneR = `So;
                    12'd270: toneR = `So;    12'd271: toneR = `So;

                    12'd272: toneR = `Re2;    12'd273: toneR = `Re2;
                    12'd274: toneR = `Re2;    12'd275: toneR = `Re2;
                    12'd276: toneR = `Re2;    12'd277: toneR = `Re2;
                    12'd278: toneR = `Re2;    12'd279: toneR = `Re2;
                    12'd280: toneR = `Re2;    12'd281: toneR = `Re2;
                    12'd282: toneR = `Re2;    12'd283: toneR = `Re2;    
                    12'd284: toneR = `Re2;    12'd285: toneR = `Re2;
                    12'd286: toneR = `Re2;    12'd287: toneR = `Re2;

                    12'd288: toneR = `Mi2_down;    12'd289: toneR = `Mi2_down;
                    12'd290: toneR = `Mi2_down;    12'd291: toneR = `Mi2_down;
                    12'd292: toneR = `Mi2_down;    12'd293: toneR = `Mi2_down;
                    12'd294: toneR = `Mi2_down;    12'd295: toneR = `Mi2_down;
                    12'd296: toneR = `Re2;    12'd297: toneR = `Re2;
                    12'd298: toneR = `Re2;    12'd299: toneR = `Re2;
                    12'd300: toneR = `Re2;    12'd301: toneR = `Re2;
                    12'd302: toneR = `Re2;    12'd303: toneR = `Re2;

                    12'd304: toneR = `Do2;    12'd305: toneR = `Do2;    
                    12'd306: toneR = `Do2;    12'd307: toneR = `Do2;
                    12'd308: toneR = `Do2;    12'd309: toneR = `Do2;
                    12'd310: toneR = `Do2;    12'd311: toneR = `Do2;
                    12'd312: toneR = `Si2_down;    12'd313: toneR = `Si2_down;
                    12'd314: toneR = `Si2_down;    12'd315: toneR = `Si2_down;
                    12'd316: toneR = `Si2_down;    12'd317: toneR = `Si2_down;
                    12'd318: toneR = `Si2_down;    12'd319: toneR = `Si2_down;

                    12'd320: toneR = `Re2;    12'd321: toneR = `Re2;
                    12'd322: toneR = `Re2;    12'd323: toneR = `Re2;    
                    12'd324: toneR = `Re2;    12'd325: toneR = `Re2;
                    12'd326: toneR = `Re2;    12'd327: toneR = `Re2;
                    12'd328: toneR = `Do2;    12'd329: toneR = `Do2;
                    12'd330: toneR = `Do2;    12'd331: toneR = `Do2;
                    12'd332: toneR = `Do2;    12'd333: toneR = `Do2;
                    12'd334: toneR = `Do2;    12'd335: toneR = `Do2;

                    12'd336: toneR = `Re2;    12'd337: toneR = `Re2;
                    12'd338: toneR = `Re2;    12'd339: toneR = `Re2;
                    12'd340: toneR = `Re2;    12'd341: toneR = `Re2;
                    12'd342: toneR = `Re2;    12'd343: toneR = `Re2;
                    12'd344: toneR = `Re2;    12'd345: toneR = `Re2;    
                    12'd346: toneR = `Re2;    12'd347: toneR = `Re2;
                    12'd348: toneR = `Re2;    12'd349: toneR = `Re2;
                    12'd350: toneR = `Re2;    12'd351: toneR = `Re2;

                    12'd352: toneR = `So;    12'd353: toneR = `So;
                    12'd354: toneR = `So;    12'd355: toneR = `So;
                    12'd356: toneR = `So;    12'd357: toneR = `So;
                    12'd358: toneR = `So;    12'd359: toneR = `So;
                    12'd360: toneR = `So;    12'd361: toneR = `So;
                    12'd362: toneR = `So;    12'd363: toneR = `So;    
                    12'd364: toneR = `So;    12'd365: toneR = `So;
                    12'd366: toneR = `So;    12'd367: toneR = `So;

                    12'd368: toneR = `So;    12'd369: toneR = `So;
                    12'd370: toneR = `So;    12'd371: toneR = `So;
                    12'd372: toneR = `So;    12'd373: toneR = `So;
                    12'd374: toneR = `So;    12'd375: toneR = `So;
                    12'd376: toneR = `Si2_down;    12'd377: toneR = `Si2_down;
                    12'd378: toneR = `Si2_down;    12'd379: toneR = `Si2_down;    
                    12'd380: toneR = `Si2_down;    12'd381: toneR = `Si2_down;
                    12'd382: toneR = `Si2_down;    12'd383: toneR = `Si2_down;

                    12'd384: toneR = `La;    12'd385: toneR = `La;
                    12'd386: toneR = `La;    12'd387: toneR = `La;
                    12'd388: toneR = `La;    12'd389: toneR = `La;
                    12'd390: toneR = `La;    12'd391: toneR = `La;
                    12'd392: toneR = `La;    12'd393: toneR = `La;
                    12'd394: toneR = `La;    12'd395: toneR = `La;
                    12'd396: toneR = `La;    12'd397: toneR = `La;    
                    12'd398: toneR = `La;    12'd399: toneR = `sil;

                    12'd400: toneR = `La;    12'd401: toneR = `La;
                    12'd402: toneR = `La;    12'd403: toneR = `La;
                    12'd404: toneR = `La;    12'd405: toneR = `La;
                    12'd406: toneR = `La;    12'd407: toneR = `La;
                    12'd408: toneR = `La;    12'd409: toneR = `La;
                    12'd410: toneR = `La;    12'd411: toneR = `La;
                    12'd412: toneR = `La;    12'd413: toneR = `La;
                    12'd414: toneR = `La;    12'd415: toneR = `La;    

                    12'd416: toneR = `Re2;    12'd417: toneR = `Re2;
                    12'd418: toneR = `Re2;    12'd419: toneR = `Re2;
                    12'd420: toneR = `Re2;    12'd421: toneR = `Re2;
                    12'd422: toneR = `Re2;    12'd423: toneR = `Re2;
                    12'd424: toneR = `Re2;    12'd425: toneR = `Re2;
                    12'd426: toneR = `Re2;    12'd427: toneR = `Re2;
                    12'd428: toneR = `Re2;    12'd429: toneR = `Re2;
                    12'd430: toneR = `Re2;    12'd431: toneR = `Re2;

                    12'd432: toneR = `Do2;    12'd433: toneR = `Do2;
                    12'd434: toneR = `Do2;    12'd435: toneR = `Do2;    
                    12'd436: toneR = `Do2;    12'd437: toneR = `Do2;
                    12'd438: toneR = `Do2;    12'd439: toneR = `Do2;
                    12'd440: toneR = `Do2;    12'd441: toneR = `Do2;
                    12'd442: toneR = `Do2;    12'd443: toneR = `Do2;
                    12'd444: toneR = `Do2;    12'd445: toneR = `Do2;
                    12'd446: toneR = `Do2;    12'd447: toneR = `Do2;

                    12'd448: toneR = `Si2_down;    12'd449: toneR = `Si2_down;
                    12'd450: toneR = `Si2_down;    12'd451: toneR = `Si2_down;
                    12'd452: toneR = `Si2_down;    12'd453: toneR = `Si2_down;
                    12'd454: toneR = `Si2_down;    12'd455: toneR = `Si2_down;
                    12'd456: toneR = `Si2_down;    12'd457: toneR = `Si2_down;
                    12'd458: toneR = `Si2_down;    12'd459: toneR = `Si2_down;
                    12'd460: toneR = `Si2_down;    12'd461: toneR = `Si2_down;
                    12'd462: toneR = `Si2_down;    12'd463: toneR = `Si2_down;

                    12'd464: toneR = `Si2_down;    12'd465: toneR = `Si2_down;    
                    12'd466: toneR = `Si2_down;    12'd467: toneR = `Si2_down;    
                    12'd468: toneR = `Si2_down;    12'd469: toneR = `Si2_down;    
                    12'd470: toneR = `Si2_down;    12'd471: toneR = `Si2_down;
                    12'd472: toneR = `Si2_down;    12'd473: toneR = `Si2_down;
                    12'd474: toneR = `Si2_down;    12'd475: toneR = `Si2_down;
                    12'd476: toneR = `Si2_down;    12'd477: toneR = `Si2_down;
                    12'd478: toneR = `Si2_down;    12'd479: toneR = `Si2_down;

                    12'd480: toneR = `Si2_down;    12'd481: toneR = `Si2_down;    
                    12'd482: toneR = `Si2_down;    12'd483: toneR = `Si2_down;
                    12'd484: toneR = `Si2_down;    12'd485: toneR = `Si2_down;
                    12'd486: toneR = `Si2_down;    12'd487: toneR = `Si2_down;
                    12'd488: toneR = `Si2_down;    12'd489: toneR = `Si2_down;
                    12'd490: toneR = `Si2_down;    12'd491: toneR = `Si2_down;
                    12'd492: toneR = `Si2_down;    12'd493: toneR = `Si2_down;
                    12'd494: toneR = `Si2_down;    12'd495: toneR = `Si2_down;

                    12'd496: toneR = `Si2_down;    12'd497: toneR = `Si2_down;
                    12'd498: toneR = `Si2_down;    12'd499: toneR = `Si2_down;
                    12'd500: toneR = `Si2_down;    12'd501: toneR = `Si2_down;    
                    12'd502: toneR = `Si2_down;    12'd503: toneR = `Si2_down;
                    12'd504: toneR = `Si2_down;    12'd505: toneR = `Si2_down;
                    12'd506: toneR = `Si2_down;    12'd507: toneR = `Si2_down;
                    12'd508: toneR = `Si2_down;    12'd509: toneR = `Si2_down;
                    12'd510: toneR = `Si2_down;    12'd511: toneR = `Si2_down; 
                    default: toneR = `sil;
                endcase
            end
        end else begin
            if(key_down[last_change] == 1 && last_change == 9'b0_0001_1100)toneR = `Do;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0001_1011)toneR = `Re;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0010_0011)toneR = `Mi;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0010_1011)toneR = `Fa;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0011_0100)toneR = `So;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0011_0011)toneR = `La;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0011_1011)toneR = `Si;
            else toneR = `sil;

        end
    end

    always @(*) begin
        if(mode == 1)begin
            if(music)begin
                case(ibeatNum)
                    12'd0: toneL = `Do1;    12'd1: toneL = `Do1;    
                    12'd2: toneL = `Do1;    12'd3: toneL = `Do1;
                    12'd4: toneL = `Do1;    12'd5: toneL = `Do1;
                    12'd6: toneL = `Do1;    12'd7: toneL = `Do1;
                    12'd8: toneL = `Do1;    12'd9: toneL = `Do1;
                    12'd10: toneL = `Do1;    12'd11: toneL = `Do1;
                    12'd12: toneL = `Do1;    12'd13: toneL = `Do1;
                    12'd14: toneL = `Do1;    12'd15: toneL = `Do1;

                    12'd16: toneL = `So1;    12'd17: toneL = `So1;
                    12'd18: toneL = `So1;    12'd19: toneL = `So1;
                    12'd20: toneL = `So1;    12'd21: toneL = `So1;
                    12'd22: toneL = `So1;    12'd23: toneL = `So1;
                    12'd24: toneL = `So1;    12'd25: toneL = `So1;
                    12'd26: toneL = `So1;    12'd27: toneL = `So1;
                    12'd28: toneL = `So1;    12'd29: toneL = `So1;    
                    12'd30: toneL = `So1;    12'd31: toneL = `So1;

                    12'd32: toneL = `So0;    12'd33: toneL = `So0;
                    12'd34: toneL = `So0;    12'd35: toneL = `So0;
                    12'd36: toneL = `So0;    12'd37: toneL = `So0;
                    12'd38: toneL = `So0;    12'd39: toneL = `So0;
                    12'd40: toneL = `So0;    12'd41: toneL = `So0;
                    12'd42: toneL = `So0;    12'd43: toneL = `So0;
                    12'd44: toneL = `So0;    12'd45: toneL = `So0;
                    12'd46: toneL = `So0;    12'd47: toneL = `So0;

                    12'd48: toneL = `So1;    12'd49: toneL = `So1;
                    12'd50: toneL = `So1;    12'd51: toneL = `So1;
                    12'd52: toneL = `So1;    12'd53: toneL = `So1;
                    12'd54: toneL = `So1;    12'd55: toneL = `So1;
                    12'd56: toneL = `So1;    12'd57: toneL = `So1;
                    12'd58: toneL = `So1;    12'd59: toneL = `So1;
                    12'd60: toneL = `So1;    12'd61: toneL = `So1;
                    12'd62: toneL = `So1;    12'd63: toneL = `So1;

                    12'd64: toneL = `Do1;    12'd65: toneL = `Do1;    
                    12'd66: toneL = `Do1;    12'd67: toneL = `Do1;
                    12'd68: toneL = `Do1;    12'd69: toneL = `Do1;
                    12'd70: toneL = `Do1;    12'd71: toneL = `Do1;
                    12'd72: toneL = `Do1;    12'd73: toneL = `Do1;
                    12'd74: toneL = `Do1;    12'd75: toneL = `Do1;
                    12'd76: toneL = `Do1;    12'd77: toneL = `Do1;
                    12'd78: toneL = `Do1;    12'd79: toneL = `Do1;

                    12'd80: toneL = `So1;    12'd81: toneL = `So1;
                    12'd82: toneL = `So1;    12'd83: toneL = `So1;
                    12'd84: toneL = `So1;    12'd85: toneL = `So1;    
                    12'd86: toneL = `So1;    12'd87: toneL = `So1;
                    12'd88: toneL = `So1;    12'd89: toneL = `So1;
                    12'd90: toneL = `So1;    12'd91: toneL = `So1;
                    12'd92: toneL = `So1;    12'd93: toneL = `So1;
                    12'd94: toneL = `So1;    12'd95: toneL = `So1;

                    12'd96: toneL = `So0;    12'd97: toneL = `So0;
                    12'd98: toneL = `So0;    12'd99: toneL = `So0;
                    12'd100: toneL = `So0;    12'd101: toneL = `So0;
                    12'd102: toneL = `So0;    12'd103: toneL = `So0;
                    12'd104: toneL = `So0;    12'd105: toneL = `So0;
                    12'd106: toneL = `So0;    12'd107: toneL = `So0;    
                    12'd108: toneL = `So0;    12'd109: toneL = `So0;
                    12'd110: toneL = `So0;    12'd111: toneL = `So0;

                    12'd112: toneL = `So1;    12'd113: toneL = `So1;
                    12'd114: toneL = `So1;    12'd115: toneL = `So1;
                    12'd116: toneL = `So1;    12'd117: toneL = `So1;
                    12'd118: toneL = `So1;    12'd119: toneL = `So1;
                    12'd120: toneL = `So1;    12'd121: toneL = `So1;
                    12'd122: toneL = `So1;    12'd123: toneL = `So1;
                    12'd124: toneL = `So1;    12'd125: toneL = `So1;
                    12'd126: toneL = `So1;    12'd127: toneL = `So1;    

                    12'd128: toneL = `Fa0;    12'd129: toneL = `Fa0;
                    12'd130: toneL = `Fa0;    12'd131: toneL = `Fa0;
                    12'd132: toneL = `Fa0;    12'd133: toneL = `Fa0;
                    12'd134: toneL = `Fa0;    12'd135: toneL = `Fa0;
                    12'd136: toneL = `Fa0;    12'd137: toneL = `Fa0;
                    12'd138: toneL = `Fa0;    12'd139: toneL = `Fa0;
                    12'd140: toneL = `Fa0;    12'd141: toneL = `Fa0;
                    12'd142: toneL = `Fa0;    12'd143: toneL = `Fa0;

                    12'd144: toneL = `Fa1;    12'd145: toneL = `Fa1;
                    12'd146: toneL = `Fa1;    12'd147: toneL = `Fa1;
                    12'd148: toneL = `Fa1;    12'd149: toneL = `Fa1;    
                    12'd150: toneL = `Fa1;    12'd151: toneL = `Fa1;
                    12'd152: toneL = `Fa1;    12'd153: toneL = `Fa1;
                    12'd154: toneL = `Fa1;    12'd155: toneL = `Fa1;
                    12'd156: toneL = `Fa1;    12'd157: toneL = `Fa1;
                    12'd158: toneL = `Fa1;    12'd159: toneL = `Fa1;

                    12'd160: toneL = `Fa0;    12'd161: toneL = `Fa0;
                    12'd162: toneL = `Fa0;    12'd163: toneL = `Fa0;
                    12'd164: toneL = `Fa0;    12'd165: toneL = `Fa0;
                    12'd166: toneL = `Fa0;    12'd167: toneL = `Fa0;
                    12'd168: toneL = `Fa0;    12'd169: toneL = `Fa0;
                    12'd170: toneL = `Fa0;    12'd171: toneL = `Fa0;    
                    12'd172: toneL = `Fa0;    12'd173: toneL = `Fa0;
                    12'd174: toneL = `Fa0;    12'd175: toneL = `Fa0;

                    12'd176: toneL = `Fa1;    12'd177: toneL = `Fa1;
                    12'd178: toneL = `Fa1;    12'd179: toneL = `Fa1;
                    12'd180: toneL = `Fa1;    12'd181: toneL = `Fa1;
                    12'd182: toneL = `Fa1;    12'd183: toneL = `Fa1;
                    12'd184: toneL = `Fa1;    12'd185: toneL = `Fa1;
                    12'd186: toneL = `Fa1;    12'd187: toneL = `Fa1;
                    12'd188: toneL = `Fa1;    12'd189: toneL = `Fa1;
                    12'd190: toneL = `Fa1;    12'd191: toneL = `Fa1;

                    12'd192: toneL = `Do1;    12'd193: toneL = `Do1;
                    12'd194: toneL = `Do1;    12'd195: toneL = `Do1;    
                    12'd196: toneL = `Do1;    12'd197: toneL = `Do1;
                    12'd198: toneL = `Do1;    12'd199: toneL = `Do1;
                    12'd200: toneL = `Do1;    12'd201: toneL = `Do1;
                    12'd202: toneL = `Do1;    12'd203: toneL = `Do1;
                    12'd204: toneL = `Do1;    12'd205: toneL = `Do1;
                    12'd206: toneL = `Do1;    12'd207: toneL = `Do1;

                    12'd208: toneL = `So0;    12'd209: toneL = `So0;
                    12'd210: toneL = `So0;    12'd211: toneL = `So0;
                    12'd212: toneL = `So0;    12'd213: toneL = `So0;
                    12'd214: toneL = `So0;    12'd215: toneL = `So0;    
                    12'd216: toneL = `So0;    12'd217: toneL = `So0;
                    12'd218: toneL = `So0;    12'd219: toneL = `So0;
                    12'd220: toneL = `So0;    12'd221: toneL = `So0;
                    12'd222: toneL = `So0;    12'd223: toneL = `So0;

                    12'd224: toneL = `La0;    12'd225: toneL = `La0;
                    12'd226: toneL = `La0;    12'd227: toneL = `La0;
                    12'd228: toneL = `La0;    12'd229: toneL = `La0;
                    12'd230: toneL = `La0;    12'd231: toneL = `La0;
                    12'd232: toneL = `La0;    12'd233: toneL = `La0;
                    12'd234: toneL = `La0;    12'd235: toneL = `La0;    
                    12'd236: toneL = `La0;    12'd237: toneL = `La0;
                    12'd238: toneL = `La0;    12'd239: toneL = `La0;

                    12'd240: toneL = `Si0;    12'd241: toneL = `Si0;
                    12'd242: toneL = `Si0;    12'd243: toneL = `Si0;
                    12'd244: toneL = `Si0;    12'd245: toneL = `Si0;
                    12'd246: toneL = `Si0;    12'd247: toneL = `Si0;
                    12'd248: toneL = `Si0;    12'd249: toneL = `Si0;
                    12'd250: toneL = `Si0;    12'd251: toneL = `Si0;
                    12'd252: toneL = `Si0;    12'd253: toneL = `Si0;
                    12'd254: toneL = `Si0;    12'd255: toneL = `Si0;

                    12'd256: toneL = `Do1;    12'd257: toneL = `Do1;
                    12'd258: toneL = `Do1;    12'd259: toneL = `Do1;
                    12'd260: toneL = `Do1;    12'd261: toneL = `Do1;
                    12'd262: toneL = `Do1;    12'd263: toneL = `Do1;
                    12'd264: toneL = `Do1;    12'd265: toneL = `Do1;
                    12'd266: toneL = `Do1;    12'd267: toneL = `Do1;
                    12'd268: toneL = `Do1;    12'd269: toneL = `Do1;
                    12'd270: toneL = `Do1;    12'd271: toneL = `Do1;

                    12'd272: toneL = `So1;    12'd273: toneL = `So1;
                    12'd274: toneL = `So1;    12'd275: toneL = `So1;
                    12'd276: toneL = `So1;    12'd277: toneL = `So1;    
                    12'd278: toneL = `So1;    12'd279: toneL = `So1;
                    12'd280: toneL = `So1;    12'd281: toneL = `So1;
                    12'd282: toneL = `So1;    12'd283: toneL = `So1;
                    12'd284: toneL = `So1;    12'd285: toneL = `So1;
                    12'd286: toneL = `So1;    12'd287: toneL = `So1;

                    12'd288: toneL = `So0;    12'd289: toneL = `So0;
                    12'd290: toneL = `So0;    12'd291: toneL = `So0;
                    12'd292: toneL = `So0;    12'd293: toneL = `So0;
                    12'd294: toneL = `So0;    12'd295: toneL = `So0;
                    12'd296: toneL = `So0;    12'd297: toneL = `So0;
                    12'd298: toneL = `So0;    12'd299: toneL = `So0;    
                    12'd300: toneL = `So0;    12'd301: toneL = `So0;
                    12'd302: toneL = `So0;    12'd303: toneL = `So0;

                    12'd304: toneL = `So1;    12'd305: toneL = `So1;
                    12'd306: toneL = `So1;    12'd307: toneL = `So1;
                    12'd308: toneL = `So1;    12'd309: toneL = `So1;
                    12'd310: toneL = `So1;    12'd311: toneL = `So1;
                    12'd312: toneL = `So1;    12'd313: toneL = `So1;
                    12'd314: toneL = `So1;    12'd315: toneL = `So1;
                    12'd316: toneL = `So1;    12'd317: toneL = `So1;
                    12'd318: toneL = `So1;    12'd319: toneL = `So1;

                    12'd320: toneL = `Do1;    12'd321: toneL = `Do1;
                    12'd322: toneL = `Do1;    12'd323: toneL = `Do1;    
                    12'd324: toneL = `Do1;    12'd325: toneL = `Do1;
                    12'd326: toneL = `Do1;    12'd327: toneL = `Do1;
                    12'd328: toneL = `Do1;    12'd329: toneL = `Do1;
                    12'd330: toneL = `Do1;    12'd331: toneL = `Do1;
                    12'd332: toneL = `Do1;    12'd333: toneL = `Do1;
                    12'd334: toneL = `Do1;    12'd335: toneL = `Do1;

                    12'd336: toneL = `So1;    12'd337: toneL = `So1;
                    12'd338: toneL = `So1;    12'd339: toneL = `So1;
                    12'd340: toneL = `So1;    12'd341: toneL = `So1;
                    12'd342: toneL = `So1;    12'd343: toneL = `So1;
                    12'd344: toneL = `So1;    12'd345: toneL = `So1;
                    12'd346: toneL = `So1;    12'd347: toneL = `So1;
                    12'd348: toneL = `So1;    12'd349: toneL = `So1;    
                    12'd350: toneL = `So1;    12'd351: toneL = `So1;

                    12'd352: toneL = `So0;    12'd353: toneL = `So0;
                    12'd354: toneL = `So0;    12'd355: toneL = `So0;
                    12'd356: toneL = `So0;    12'd357: toneL = `So0;
                    12'd358: toneL = `So0;    12'd359: toneL = `So0;
                    12'd360: toneL = `So0;    12'd361: toneL = `So0;
                    12'd362: toneL = `So0;    12'd363: toneL = `So0;
                    12'd364: toneL = `So0;    12'd365: toneL = `So0;
                    12'd366: toneL = `So0;    12'd367: toneL = `So0;

                    12'd368: toneL = `So1;    12'd369: toneL = `So1;
                    12'd370: toneL = `So1;    12'd371: toneL = `So1;
                    12'd372: toneL = `So1;    12'd373: toneL = `So1;    
                    12'd374: toneL = `So1;    12'd375: toneL = `So1;
                    12'd376: toneL = `So1;    12'd377: toneL = `So1;
                    12'd378: toneL = `So1;    12'd379: toneL = `So1;
                    12'd380: toneL = `So1;    12'd381: toneL = `So1;
                    12'd382: toneL = `So1;    12'd383: toneL = `So1;

                    12'd384: toneL = `Fa0;    12'd385: toneL = `Fa0;
                    12'd386: toneL = `Fa0;    12'd387: toneL = `Fa0;
                    12'd388: toneL = `Fa0;    12'd389: toneL = `Fa0;
                    12'd390: toneL = `Fa0;    12'd391: toneL = `Fa0;    
                    12'd392: toneL = `Fa0;    12'd393: toneL = `Fa0;
                    12'd394: toneL = `Fa0;    12'd395: toneL = `Fa0;
                    12'd396: toneL = `Fa0;    12'd397: toneL = `Fa0;
                    12'd398: toneL = `Fa0;    12'd399: toneL = `Fa0;

                    12'd400: toneL = `Fa1;    12'd401: toneL = `Fa1;
                    12'd402: toneL = `Fa1;    12'd403: toneL = `Fa1;
                    12'd404: toneL = `Fa1;    12'd405: toneL = `Fa1;
                    12'd406: toneL = `Fa1;    12'd407: toneL = `Fa1;
                    12'd408: toneL = `Fa1;    12'd409: toneL = `Fa1;
                    12'd410: toneL = `Fa1;    12'd411: toneL = `Fa1;
                    12'd412: toneL = `Fa1;    12'd413: toneL = `Fa1;
                    12'd414: toneL = `Fa1;    12'd415: toneL = `Fa1;

                    12'd416: toneL = `Fa0;    12'd417: toneL = `Fa0;
                    12'd418: toneL = `Fa0;    12'd419: toneL = `Fa0;
                    12'd420: toneL = `Fa0;    12'd421: toneL = `Fa0;
                    12'd422: toneL = `Fa0;    12'd423: toneL = `Fa0;
                    12'd424: toneL = `Fa0;    12'd425: toneL = `Fa0;
                    12'd426: toneL = `Fa0;    12'd427: toneL = `Fa0;
                    12'd428: toneL = `Fa0;    12'd429: toneL = `Fa0;
                    12'd430: toneL = `Fa0;    12'd431: toneL = `Fa0;

                    12'd432: toneL = `Fa1;    12'd433: toneL = `Fa1;
                    12'd434: toneL = `Fa1;    12'd435: toneL = `Fa1;
                    12'd436: toneL = `Fa1;    12'd437: toneL = `Fa1;    
                    12'd438: toneL = `Fa1;    12'd439: toneL = `Fa1;
                    12'd440: toneL = `Fa1;    12'd441: toneL = `Fa1;
                    12'd442: toneL = `Fa1;    12'd443: toneL = `Fa1;
                    12'd444: toneL = `Fa1;    12'd445: toneL = `Fa1;
                    12'd446: toneL = `Fa1;    12'd447: toneL = `Fa1;

                    12'd448: toneL = `Do1;    12'd449: toneL = `Do1;
                    12'd450: toneL = `Do1;    12'd451: toneL = `Do1;
                    12'd452: toneL = `Do1;    12'd453: toneL = `Do1;
                    12'd454: toneL = `Do1;    12'd455: toneL = `Do1;
                    12'd456: toneL = `Do1;    12'd457: toneL = `Do1;
                    12'd458: toneL = `Do1;    12'd459: toneL = `Do1;
                    12'd460: toneL = `Do1;    12'd461: toneL = `Do1;    
                    12'd462: toneL = `Do1;    12'd463: toneL = `Do1;

                    12'd464: toneL = `So0;    12'd465: toneL = `So0;
                    12'd466: toneL = `So0;    12'd467: toneL = `So0;
                    12'd468: toneL = `So0;    12'd469: toneL = `So0;
                    12'd470: toneL = `So0;    12'd471: toneL = `So0;
                    12'd472: toneL = `So0;    12'd473: toneL = `So0;
                    12'd474: toneL = `So0;    12'd475: toneL = `So0;
                    12'd476: toneL = `So0;    12'd477: toneL = `So0;
                    12'd478: toneL = `So0;    12'd479: toneL = `So0;

                    12'd480: toneL = `Do0;    12'd481: toneL = `Do0;
                    12'd482: toneL = `Do0;    12'd483: toneL = `Do0;
                    12'd484: toneL = `Do0;    12'd485: toneL = `Do0;    
                    12'd486: toneL = `Do0;    12'd487: toneL = `Do0;
                    12'd488: toneL = `Do0;    12'd489: toneL = `Do0;
                    12'd490: toneL = `Do0;    12'd491: toneL = `Do0;
                    12'd492: toneL = `Do0;    12'd493: toneL = `Do0;
                    12'd494: toneL = `Do0;    12'd495: toneL = `Do0;

                    12'd496: toneL = `Do0;    12'd497: toneL = `Do0;
                    12'd498: toneL = `Do0;    12'd499: toneL = `Do0;
                    12'd500: toneL = `Do0;    12'd501: toneL = `Do0;
                    12'd502: toneL = `Do0;    12'd503: toneL = `Do0;
                    12'd504: toneL = `Do0;    12'd505: toneL = `Do0;
                    12'd506: toneL = `Do0;    12'd507: toneL = `Do0;
                    12'd508: toneL = `Do0;    12'd509: toneL = `Do0;    
                    12'd510: toneL = `Do0;    12'd511: toneL = `Do0;
                    default : toneL = `sil;
                endcase
            end else begin
                case(ibeatNum)
                    12'd0: toneL = `sil;    12'd1: toneL = `sil;    
                    12'd2: toneL = `sil;    12'd3: toneL = `sil;
                    12'd4: toneL = `sil;    12'd5: toneL = `sil;
                    12'd6: toneL = `sil;    12'd7: toneL = `sil;
                    12'd8: toneL = `sil;    12'd9: toneL = `sil;
                    12'd10: toneL = `sil;    12'd11: toneL = `sil;
                    12'd12: toneL = `sil;    12'd13: toneL = `sil;
                    12'd14: toneL = `sil;    12'd15: toneL = `sil;

                    12'd16: toneL = `sil;    12'd17: toneL = `sil;
                    12'd18: toneL = `sil;    12'd19: toneL = `sil;
                    12'd20: toneL = `sil;    12'd21: toneL = `sil;
                    12'd22: toneL = `sil;    12'd23: toneL = `sil;
                    12'd24: toneL = `sil;    12'd25: toneL = `sil;    
                    12'd26: toneL = `sil;    12'd27: toneL = `sil;
                    12'd28: toneL = `sil;    12'd29: toneL = `sil;
                    12'd30: toneL = `sil;    12'd31: toneL = `sil;

                    12'd32: toneL = `sil;    12'd33: toneL = `sil;
                    12'd34: toneL = `sil;    12'd35: toneL = `sil;
                    12'd36: toneL = `sil;    12'd37: toneL = `sil;
                    12'd38: toneL = `sil;    12'd39: toneL = `sil;
                    12'd40: toneL = `sil;    12'd41: toneL = `sil;
                    12'd42: toneL = `sil;    12'd43: toneL = `sil;
                    12'd44: toneL = `sil;    12'd45: toneL = `sil;
                    12'd46: toneL = `sil;    12'd47: toneL = `sil;    

                    12'd48: toneL = `sil;    12'd49: toneL = `sil;
                    12'd50: toneL = `sil;    12'd51: toneL = `sil;
                    12'd52: toneL = `sil;    12'd53: toneL = `sil;
                    12'd54: toneL = `sil;    12'd55: toneL = `sil;
                    12'd56: toneL = `sil;    12'd57: toneL = `sil;
                    12'd58: toneL = `sil;    12'd59: toneL = `sil;    
                    12'd60: toneL = `sil;    12'd61: toneL = `sil;
                    12'd62: toneL = `sil;    12'd63: toneL = `sil;

                    12'd64: toneL = `Mi0;    12'd65: toneL = `Mi0;
                    12'd66: toneL = `Mi0;    12'd67: toneL = `Mi0;
                    12'd68: toneL = `Mi0;    12'd69: toneL = `Mi0;
                    12'd70: toneL = `Mi0;    12'd71: toneL = `Mi0;
                    12'd72: toneL = `Si0;    12'd73: toneL = `Si0;    
                    12'd74: toneL = `Si0;    12'd75: toneL = `Si0;
                    12'd76: toneL = `Si0;    12'd77: toneL = `Si0;
                    12'd78: toneL = `Si0;    12'd79: toneL = `Si0;

                    12'd80: toneL = `Mi1_down;    12'd81: toneL = `Mi1_down;
                    12'd82: toneL = `Mi1_down;    12'd83: toneL = `Mi1_down;
                    12'd84: toneL = `Mi1_down;    12'd85: toneL = `Mi1_down;
                    12'd86: toneL = `Mi1_down;    12'd87: toneL = `Mi1_down;
                    12'd88: toneL = `So1;    12'd89: toneL = `So1;
                    12'd90: toneL = `So1;    12'd91: toneL = `So1;    
                    12'd92: toneL = `So1;    12'd93: toneL = `So1;
                    12'd94: toneL = `So1;    12'd95: toneL = `So1;

                    12'd96: toneL = `Si1;    12'd97: toneL = `Si1;
                    12'd98: toneL = `Si1;    12'd99: toneL = `Si1;
                    12'd100: toneL = `Si1;    12'd101: toneL = `Si1;
                    12'd102: toneL = `Si1;    12'd103: toneL = `Si1;
                    12'd104: toneL = `Si1;    12'd105: toneL = `Si1;
                    12'd106: toneL = `Si1;    12'd107: toneL = `Si1;    
                    12'd108: toneL = `Si1;    12'd109: toneL = `Si1;
                    12'd110: toneL = `Si1;    12'd111: toneL = `Si1;

                    12'd112: toneL = `So1;    12'd113: toneL = `So1;
                    12'd114: toneL = `So1;    12'd115: toneL = `So1;
                    12'd116: toneL = `So1;    12'd117: toneL = `So1;
                    12'd118: toneL = `So1;    12'd119: toneL = `So1;
                    12'd120: toneL = `So1;    12'd121: toneL = `So1;
                    12'd122: toneL = `So1;    12'd123: toneL = `So1;    
                    12'd124: toneL = `So1;    12'd125: toneL = `So1;
                    12'd126: toneL = `So1;    12'd127: toneL = `So1;

                    12'd128: toneL = `Fa0;    12'd129: toneL = `Fa0;
                    12'd130: toneL = `Fa0;    12'd131: toneL = `Fa0;
                    12'd132: toneL = `Fa0;    12'd133: toneL = `Fa0;
                    12'd134: toneL = `Fa0;    12'd135: toneL = `Fa0;
                    12'd136: toneL = `Do1;    12'd137: toneL = `Do1;
                    12'd138: toneL = `Do1;    12'd139: toneL = `Do1;    
                    12'd140: toneL = `Do1;    12'd141: toneL = `Do1;
                    12'd142: toneL = `Do1;    12'd143: toneL = `Do1;

                    12'd144: toneL = `Fa1;    12'd145: toneL = `Fa1;
                    12'd146: toneL = `Fa1;    12'd147: toneL = `Fa1;
                    12'd148: toneL = `Fa1;    12'd149: toneL = `Fa1;
                    12'd150: toneL = `Fa1;    12'd151: toneL = `Fa1;
                    12'd152: toneL = `La1;    12'd153: toneL = `La1;
                    12'd154: toneL = `La1;    12'd155: toneL = `La1;
                    12'd156: toneL = `La1;    12'd157: toneL = `La1;
                    12'd158: toneL = `La1;    12'd159: toneL = `La1;    

                    12'd160: toneL = `Do;    12'd161: toneL = `Do;
                    12'd162: toneL = `Do;    12'd163: toneL = `Do;
                    12'd164: toneL = `Do;    12'd165: toneL = `Do;
                    12'd166: toneL = `Do;    12'd167: toneL = `Do;
                    12'd168: toneL = `Do;    12'd169: toneL = `Do;
                    12'd170: toneL = `Do;    12'd171: toneL = `Do;
                    12'd172: toneL = `Do;    12'd173: toneL = `Do;
                    12'd174: toneL = `Do;    12'd175: toneL = `Do;

                    12'd176: toneL = `La1;    12'd177: toneL = `La1;
                    12'd178: toneL = `La1;    12'd179: toneL = `La1;    
                    12'd180: toneL = `La1;    12'd181: toneL = `La1;
                    12'd182: toneL = `La1;    12'd183: toneL = `La1;
                    12'd184: toneL = `La1;    12'd185: toneL = `La1;
                    12'd186: toneL = `La1;    12'd187: toneL = `La1;
                    12'd188: toneL = `La1;    12'd189: toneL = `La1;
                    12'd190: toneL = `La1;    12'd191: toneL = `La1;

                    12'd192: toneL = `Re0;    12'd193: toneL = `Re0;
                    12'd194: toneL = `Re0;    12'd195: toneL = `Re0;
                    12'd196: toneL = `Re0;    12'd197: toneL = `Re0;    
                    12'd198: toneL = `Re0;    12'd199: toneL = `Re0;
                    12'd200: toneL = `La0;    12'd201: toneL = `La0;
                    12'd202: toneL = `La0;    12'd203: toneL = `La0;
                    12'd204: toneL = `La0;    12'd205: toneL = `La0;
                    12'd206: toneL = `La0;    12'd207: toneL = `La0;

                    12'd208: toneL = `Re1;    12'd209: toneL = `Re1;
                    12'd210: toneL = `Re1;    12'd211: toneL = `Re1;
                    12'd212: toneL = `Re1;    12'd213: toneL = `Re1;
                    12'd214: toneL = `Re1;    12'd215: toneL = `Re1;    
                    12'd216: toneL = `Fa1;    12'd217: toneL = `Fa1;
                    12'd218: toneL = `Fa1;    12'd219: toneL = `Fa1;
                    12'd220: toneL = `Fa1;    12'd221: toneL = `Fa1;
                    12'd222: toneL = `Fa1;    12'd223: toneL = `Fa1;

                    12'd224: toneL = `La1;    12'd225: toneL = `La1;
                    12'd226: toneL = `La1;    12'd227: toneL = `La1;
                    12'd228: toneL = `La1;    12'd229: toneL = `La1;
                    12'd230: toneL = `La1;    12'd231: toneL = `La1;
                    12'd232: toneL = `La1;    12'd233: toneL = `La1;
                    12'd234: toneL = `La1;    12'd235: toneL = `La1;
                    12'd236: toneL = `La1;    12'd237: toneL = `La1;
                    12'd238: toneL = `La1;    12'd239: toneL = `La1;    

                    12'd240: toneL = `Fa1;    12'd241: toneL = `Fa1;
                    12'd242: toneL = `Fa1;    12'd243: toneL = `Fa1;
                    12'd244: toneL = `Fa1;    12'd245: toneL = `Fa1;
                    12'd246: toneL = `Fa1;    12'd247: toneL = `Fa1;
                    12'd248: toneL = `Fa1;    12'd249: toneL = `Fa1;
                    12'd250: toneL = `Fa1;    12'd251: toneL = `Fa1;
                    12'd252: toneL = `Fa1;    12'd253: toneL = `Fa1;
                    12'd254: toneL = `Fa1;    12'd255: toneL = `Fa1;    

                    12'd256: toneL = `So0;    12'd257: toneL = `So0;
                    12'd258: toneL = `So0;    12'd259: toneL = `So0;
                    12'd260: toneL = `So0;    12'd261: toneL = `So0;
                    12'd262: toneL = `So0;    12'd263: toneL = `So0;
                    12'd264: toneL = `Re1;    12'd265: toneL = `Re1;
                    12'd266: toneL = `Re1;    12'd267: toneL = `Re1;
                    12'd268: toneL = `Re1;    12'd269: toneL = `Re1;
                    12'd270: toneL = `Re1;    12'd271: toneL = `Re1;

                    12'd272: toneL = `So1;    12'd273: toneL = `So1;
                    12'd274: toneL = `So1;    12'd275: toneL = `So1;
                    12'd276: toneL = `So1;    12'd277: toneL = `So1;    
                    12'd278: toneL = `So1;    12'd279: toneL = `So1;
                    12'd280: toneL = `Si1;    12'd281: toneL = `Si1;
                    12'd282: toneL = `Si1;    12'd283: toneL = `Si1;
                    12'd284: toneL = `Si1;    12'd285: toneL = `Si1;
                    12'd286: toneL = `Si1;    12'd287: toneL = `Si1;

                    12'd288: toneL = `Re;    12'd289: toneL = `Re;
                    12'd290: toneL = `Re;    12'd291: toneL = `Re;
                    12'd292: toneL = `Re;    12'd293: toneL = `Re;
                    12'd294: toneL = `Re;    12'd295: toneL = `Re;
                    12'd296: toneL = `Re;    12'd297: toneL = `Re;    
                    12'd298: toneL = `Re;    12'd299: toneL = `Re;
                    12'd300: toneL = `Re;    12'd301: toneL = `Re;
                    12'd302: toneL = `Re;    12'd303: toneL = `Re;

                    12'd304: toneL = `Si1;    12'd305: toneL = `Si1;
                    12'd306: toneL = `Si1;    12'd307: toneL = `Si1;
                    12'd308: toneL = `Si1;    12'd309: toneL = `Si1;
                    12'd310: toneL = `Si1;    12'd311: toneL = `Si1;
                    12'd312: toneL = `Si1;    12'd313: toneL = `Si1;    
                    12'd314: toneL = `Si1;    12'd315: toneL = `Si1;
                    12'd316: toneL = `Si1;    12'd317: toneL = `Si1;
                    12'd318: toneL = `Si1;    12'd319: toneL = `Si1;

                    12'd320: toneL = `Mi0;    12'd321: toneL = `Mi0;
                    12'd322: toneL = `Mi0;    12'd323: toneL = `Mi0;
                    12'd324: toneL = `Mi0;    12'd325: toneL = `Mi0;
                    12'd326: toneL = `Mi0;    12'd327: toneL = `Mi0;
                    12'd328: toneL = `Si0_down;    12'd329: toneL = `Si0_down;
                    12'd330: toneL = `Si0_down;    12'd331: toneL = `Si0_down;
                    12'd332: toneL = `Si0_down;    12'd333: toneL = `Si0_down;    
                    12'd334: toneL = `Si0_down;    12'd335: toneL = `Si0_down;

                    12'd336: toneL = `Mi1;    12'd337: toneL = `Mi1;
                    12'd338: toneL = `Mi1;    12'd339: toneL = `Mi1;
                    12'd340: toneL = `Mi1;    12'd341: toneL = `Mi1;
                    12'd342: toneL = `Mi1;    12'd343: toneL = `Mi1;
                    12'd344: toneL = `So1;    12'd345: toneL = `So1;
                    12'd346: toneL = `So1;    12'd347: toneL = `So1;
                    12'd348: toneL = `So1;    12'd349: toneL = `So1;
                    12'd350: toneL = `So1;    12'd351: toneL = `So1;

                    12'd352: toneL = `Si1;    12'd353: toneL = `Si1;    
                    12'd354: toneL = `Si1;    12'd355: toneL = `Si1;
                    12'd356: toneL = `Si1;    12'd357: toneL = `Si1;
                    12'd358: toneL = `Si1;    12'd359: toneL = `Si1;
                    12'd360: toneL = `Si1;    12'd361: toneL = `Si1;
                    12'd362: toneL = `Si1;    12'd363: toneL = `Si1;
                    12'd364: toneL = `Si1;    12'd365: toneL = `Si1;
                    12'd366: toneL = `Si1;    12'd367: toneL = `Si1;

                    12'd368: toneL = `So1;    12'd369: toneL = `So1;
                    12'd370: toneL = `So1;    12'd371: toneL = `So1;
                    12'd372: toneL = `So1;    12'd373: toneL = `So1;
                    12'd374: toneL = `So1;    12'd375: toneL = `So1;
                    12'd376: toneL = `So1;    12'd377: toneL = `So1;    
                    12'd378: toneL = `So1;    12'd379: toneL = `So1;
                    12'd380: toneL = `So1;    12'd381: toneL = `So1;
                    12'd382: toneL = `So1;    12'd383: toneL = `So1;

                    12'd384: toneL = `Fa0;    12'd385: toneL = `Fa0;
                    12'd386: toneL = `Fa0;    12'd387: toneL = `Fa0;
                    12'd388: toneL = `Fa0;    12'd389: toneL = `Fa0;
                    12'd390: toneL = `Fa0;    12'd391: toneL = `Fa0;
                    12'd392: toneL = `Do1;    12'd393: toneL = `Do1;
                    12'd394: toneL = `Do1;    12'd395: toneL = `Do1;
                    12'd396: toneL = `Do1;    12'd397: toneL = `Do1;
                    12'd398: toneL = `Do1;    12'd399: toneL = `Do1;    

                    12'd400: toneL = `Fa1;    12'd401: toneL = `Fa1;
                    12'd402: toneL = `Fa1;    12'd403: toneL = `Fa1;
                    12'd404: toneL = `Fa1;    12'd405: toneL = `Fa1;
                    12'd406: toneL = `Fa1;    12'd407: toneL = `Fa1;
                    12'd408: toneL = `La1;    12'd409: toneL = `La1;
                    12'd410: toneL = `La1;    12'd411: toneL = `La1;
                    12'd412: toneL = `La1;    12'd413: toneL = `La1;
                    12'd414: toneL = `La1;    12'd415: toneL = `La1;

                    12'd416: toneL = `Do;    12'd417: toneL = `Do;
                    12'd418: toneL = `Do;    12'd419: toneL = `Do;
                    12'd420: toneL = `Do;    12'd421: toneL = `Do;
                    12'd422: toneL = `Do;    12'd423: toneL = `Do;    
                    12'd424: toneL = `Do;    12'd425: toneL = `Do;
                    12'd426: toneL = `Do;    12'd427: toneL = `Do;
                    12'd428: toneL = `Do;    12'd429: toneL = `Do;
                    12'd430: toneL = `Do;    12'd431: toneL = `Do;

                    12'd432: toneL = `La1;    12'd433: toneL = `La1;
                    12'd434: toneL = `La1;    12'd435: toneL = `La1;
                    12'd436: toneL = `La1;    12'd437: toneL = `La1;
                    12'd438: toneL = `La1;    12'd439: toneL = `La1;
                    12'd440: toneL = `La1;    12'd441: toneL = `La1;
                    12'd442: toneL = `La1;    12'd443: toneL = `La1;
                    12'd444: toneL = `La1;    12'd445: toneL = `La1;
                    12'd446: toneL = `La1;    12'd447: toneL = `La1;    

                    12'd448: toneL = `Si0_down;    12'd449: toneL = `Si0_down;
                    12'd450: toneL = `Si0_down;    12'd451: toneL = `Si0_down;
                    12'd452: toneL = `Si0_down;    12'd453: toneL = `Si0_down;
                    12'd454: toneL = `Si0_down;    12'd455: toneL = `Si0_down;
                    12'd456: toneL = `Si0_down;    12'd457: toneL = `Si0_down;
                    12'd458: toneL = `Si0_down;    12'd459: toneL = `Si0_down;
                    12'd460: toneL = `Si0_down;    12'd461: toneL = `Si0_down;
                    12'd462: toneL = `Si0_down;    12'd463: toneL = `Si0_down;

                    12'd464: toneL = `Si0_down;    12'd465: toneL = `Si0_down;
                    12'd466: toneL = `Si0_down;    12'd467: toneL = `Si0_down;    
                    12'd468: toneL = `Si0_down;    12'd469: toneL = `Si0_down;
                    12'd470: toneL = `Si0_down;    12'd471: toneL = `Si0_down;
                    12'd472: toneL = `Si0_down;    12'd473: toneL = `Si0_down;
                    12'd474: toneL = `Si0_down;    12'd475: toneL = `Si0_down;
                    12'd476: toneL = `Si0_down;    12'd477: toneL = `Si0_down;
                    12'd478: toneL = `Si0_down;    12'd479: toneL = `Si0_down;

                    12'd480: toneL = `Si0_down;    12'd481: toneL = `Si0_down;
                    12'd482: toneL = `Si0_down;    12'd483: toneL = `Si0_down;
                    12'd484: toneL = `Si0_down;    12'd485: toneL = `Si0_down;
                    12'd486: toneL = `Si0_down;    12'd487: toneL = `Si0_down;
                    12'd488: toneL = `Si0_down;    12'd489: toneL = `Si0_down;
                    12'd490: toneL = `Si0_down;    12'd491: toneL = `Si0_down;
                    12'd492: toneL = `Si0_down;    12'd493: toneL = `Si0_down;    
                    12'd494: toneL = `Si0_down;    12'd495: toneL = `Si0_down;

                    12'd496: toneL = `Si0_down;    12'd497: toneL = `Si0_down;
                    12'd498: toneL = `Si0_down;    12'd499: toneL = `Si0_down;
                    12'd500: toneL = `Si0_down;    12'd501: toneL = `Si0_down;
                    12'd502: toneL = `Si0_down;    12'd503: toneL = `Si0_down;
                    12'd504: toneL = `Si0_down;    12'd505: toneL = `Si0_down;
                    12'd506: toneL = `Si0_down;    12'd507: toneL = `Si0_down;
                    12'd508: toneL = `Si0_down;    12'd509: toneL = `Si0_down;
                    12'd510: toneL = `Si0_down;    12'd511: toneL = `Si0_down;
                    default : toneL = `sil;
                endcase
            end
        end
        else begin
            if(key_down[last_change] == 1 && last_change == 9'b0_0001_1100)toneL = `Do;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0001_1011)toneL = `Re;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0010_0011)toneL = `Mi;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0010_1011)toneL = `Fa;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0011_0100)toneL = `So;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0011_0011)toneL = `La;
            else if(key_down[last_change] == 1 && last_change == 9'b0_0011_1011)toneL = `Si;
            else toneL = `sil;
        end
    end
endmodule

module note_gen(
    clk, // clock from crystal
    rst, // active high reset
    volume, 
    note_div_left, // div for note generation
    note_div_right,
    audio_left,
    audio_right
);

    // I/O declaration
    input clk; // clock from crystal
    input rst; // active low reset
    input [2:0] volume;
    input [21:0] note_div_left, note_div_right; // div for note generation
    output reg [15:0] audio_left, audio_right;

    // Declare internal signals
    reg [21:0] clk_cnt_next, clk_cnt;
    reg [21:0] clk_cnt_next_2, clk_cnt_2;
    reg b_clk, b_clk_next;
    reg c_clk, c_clk_next;

    // Note frequency generation
    // clk_cnt, clk_cnt_2, b_clk, c_clk
    always @(posedge clk or posedge rst)
        if (rst == 1'b1)
            begin
                clk_cnt <= 22'd0;
                clk_cnt_2 <= 22'd0;
                b_clk <= 1'b0;
                c_clk <= 1'b0;
            end
        else
            begin
                clk_cnt <= clk_cnt_next;
                clk_cnt_2 <= clk_cnt_next_2;
                b_clk <= b_clk_next;
                c_clk <= c_clk_next;
            end
    
    // clk_cnt_next, b_clk_next
    always @*
        if (clk_cnt == note_div_left)
            begin
                clk_cnt_next = 22'd0;
                b_clk_next = ~b_clk;
            end
        else
            begin
                clk_cnt_next = clk_cnt + 1'b1;
                b_clk_next = b_clk;
            end

    // clk_cnt_next_2, c_clk_next
    always @*
        if (clk_cnt_2 == note_div_right)
            begin
                clk_cnt_next_2 = 22'd0;
                c_clk_next = ~c_clk;
            end
        else
            begin
                clk_cnt_next_2 = clk_cnt_2 + 1'b1;
                c_clk_next = c_clk;
            end

    // Assign the amplitude of the note
    // Volume is controlled here
    always @(*) begin
        case (volume)
            0:begin
                if(b_clk == 1'b0)audio_left = 0;
                else audio_left = 0;
            end
            1:begin
                if(b_clk == 1'b0)audio_left = 16'b1111_1111_1111_1000;
                else audio_left = 16'b000000001000;
            end
            2:begin
                if(b_clk == 1'b0)audio_left = 16'b1111_1111_1100_0000;
                else audio_left = 64;
            end
            3:begin
                if(b_clk == 1'b0)audio_left = 16'b1111_1110_0000_0000;
                else audio_left = 256;
            end
            4:begin
                if(b_clk == 1'b0)audio_left = 16'b1111_0000_0000_0000;
                else audio_left = 2048;
            end
            5:begin
                if(b_clk == 1'b0)audio_left = 16'b1000_0000_0000_0000;
                else audio_left = 16384;
            end
            default:begin
                if(b_clk == 1'b0)audio_left = 0;
                else audio_left = 0;
            end
        endcase
    end

    always @(*) begin
        case (volume)
            0:begin
                if(c_clk == 1'b0)audio_right = 0;
                else audio_right = 0;
            end
            1:begin
                if(c_clk == 1'b0)audio_right = 16'b1111_1111_1111_1000;
                else audio_right = 16'b000000001000;
            end
            2:begin
                if(c_clk == 1'b0)audio_right = 16'b1111_1111_1100_0000;
                else audio_right = 64;
            end
            3:begin
                if(c_clk == 1'b0)audio_right = 16'b1111_1110_0000_0000;
                else audio_right = 256;
            end
            4:begin
                if(c_clk == 1'b0)audio_right = 16'b1111_0000_0000_0000;
                else audio_right = 2048;
            end
            5:begin
                if(c_clk == 1'b0)audio_right = 16'b1000_0000_0000_0000;
                else audio_right = 16384;
            end
            default:begin
                if(c_clk == 1'b0)audio_right = 0;
                else audio_right = 0;
            end
        endcase
    end
endmodule