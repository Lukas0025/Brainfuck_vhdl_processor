-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2020 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Lukas Plevac (xpleva07)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- ram[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_WE    : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti 
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

 constant NOP     : std_logic_vector(1 downto 0):= "00";
 constant INC     : std_logic_vector(1 downto 0):= "01";
 constant PUSH    : std_logic_vector(1 downto 0):= "01";
 constant POP     : std_logic_vector(1 downto 0):= "10";
 constant DEC     : std_logic_vector(1 downto 0):= "10";
 constant PASS_IN : std_logic_vector(1 downto 0):= "11";
 constant DIRECT  : std_logic_vector(1 downto 0):= "10";
 constant DROP    : std_logic_vector(1 downto 0):= "11";

 type ra_stack_block is array(0 to 15) of std_logic_vector(11 DOWNTO 0);
 type states is (S_FETCH, S_DECODE, S_PTR_INC, S_PTR_DEC, S_DAT_INC, S_DAT_DEC, S_DAT_SAVE, S_IN, S_OUT, S_LOOP_S, S_LOOP_E, S_LOOP_S_IF, S_F_LOOP_END, S_LOOP_E_IF, S_IDLE, S_DIRECT, S_F_LOOP_END_R, S_IN_RAM, S_OUT_RAM, S_HALT);

 signal pc_op : std_logic_vector(1 downto 0);
 signal pc_in : std_logic_vector(11 downto 0);
 signal pc_out : std_logic_vector(11 downto 0);

 signal loop_count : std_logic_vector(3 downto 0);
 signal loop_cnt_op : std_logic_vector(1 downto 0);

 signal ptr_cnt_op : std_logic_vector(1 downto 0);
 signal ptr_cnt_out : std_logic_vector(9 downto 0);

 signal ras_top : std_logic_vector(3 downto 0);
 signal ras_op : std_logic_vector(1 downto 0);
 
 signal alu_op : std_logic_vector(1 downto 0);
 signal state: states;


 signal ra_stack : ra_stack_block;

begin

 -- zde dopiste vlastni VHDL kod


 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --   - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --   - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.


  pc: process (CLK, RESET)
  begin
    if RESET = '1' then
      pc_out <= (others => '0');
    elsif rising_edge(CLK) and EN = '1' then
      if pc_op(0) = '1' then -- inc
        pc_out <= pc_out + 1;
      elsif pc_op(1) = '1' then -- diect load
        pc_out <= pc_in;
      end if;
      -- else NOP
    end if;
  end process;
  
  CODE_ADDR <= pc_out;

  loop_cnt: process (CLK, RESET)
  begin
    if RESET = '1' then
      loop_count <= (others => '0');
    elsif rising_edge(CLK) and EN = '1' then
      if loop_cnt_op(0) = '1' then -- inc
        loop_count <= loop_count + 1;
      elsif loop_cnt_op(1) = '1' then -- dec
        loop_count <= loop_count - 1;
      end if;
      -- else NOP
    end if;
  end process;

  ptr_cnt: process (CLK, RESET)
  begin
    if RESET = '1' then
      ptr_cnt_out <= (others => '0');
    elsif rising_edge(CLK) and EN = '1' then
      if ptr_cnt_op(0) = '1' then -- inc
        ptr_cnt_out <= ptr_cnt_out + 1;
      elsif ptr_cnt_op(1) = '1' then -- dec
        ptr_cnt_out <= ptr_cnt_out - 1;
      end if;
      -- else NOP
    end if;
  end process;
  
  DATA_ADDR <= ptr_cnt_out;

  ras: process (CLK, RESET)
  begin
    if RESET = '1' then
      ras_top <= "1111";
    elsif rising_edge(CLK) and EN = '1' then
	 	if ras_op = "00" then --nop (fix warning)
			ras_top <= ras_top;
      elsif ras_op = "01" then -- push
        ra_stack(conv_integer(ras_top + 1)) <= pc_out;
        ras_top <= ras_top + 1;
      elsif ras_op = "10" then -- pop
        pc_in   <= ra_stack(conv_integer(ras_top));
        ras_top <= ras_top - 1;
		elsif ras_op = "11" then --drop
			ras_top <= ras_top - 1;
      end if;
    end if;
  end process;
  
 --ALU
 DATA_WDATA <= "11111111"      when alu_op = "00" else -- fix warning
					DATA_RDATA + 1  when alu_op = "01" else
               DATA_RDATA - 1  when alu_op = "10" else
				   IN_DATA         when alu_op = "11" else
					"00000000"; -- another warning
  
 cntr: process (CLK, RESET)
 begin
  
  if RESET = '1' then
    
	 state      <= S_IDLE;
	 
	 pc_op       <= NOP;
	 ras_op      <= NOP;
	 ptr_cnt_op  <= NOP;
	 alu_op      <= NOP;
	 loop_cnt_op <= NOP;
	 
	 DATA_WE    <= '0';
	 DATA_EN    <= '0';
	 OUT_WE     <= '0';
	 IN_REQ     <= '0';
	 
  elsif rising_edge(CLK) then
	if EN = '1' then -- processor enabled
    if state = S_IDLE then
		CODE_EN    <= '1';
      
		pc_op      <= NOP;
		ptr_cnt_op <= NOP;
		alu_op     <= NOP;
		ras_op     <= NOP;
		
		OUT_WE     <= '0';
		DATA_WE    <= '0';
		DATA_EN    <= '0'; --read from ram
		IN_REQ     <= '0';
		
		state      <= S_FETCH;
	 elsif state = S_FETCH then
		CODE_EN    <= '0';
		state      <= S_DECODE;
    elsif state = S_DECODE then
		CODE_EN     <= '0';
		loop_cnt_op <= NOP;
      case conv_integer(CODE_DATA) is
        when character'pos('<') =>  state <= S_PTR_DEC;
		  when character'pos('>') =>  state <= S_PTR_INC;
        when character'pos('+') =>  state <= S_DAT_INC;
        when character'pos('-') =>  state <= S_DAT_DEC;
        when character'pos('.') =>  state <= S_OUT_RAM;
        when character'pos(',') =>  state <= S_IN;
        when character'pos('[') =>  state <= S_LOOP_S; DATA_EN <= '1'; --read from ram
        when character'pos(']') =>  state <= S_LOOP_E; DATA_EN <= '1'; --read from ram
        when 0                  =>  state <= S_HALT; --HALT
        when others             =>  state <= S_IDLE; pc_op <= INC; --load next
      end case;
	 elsif state = S_PTR_INC then
		pc_op      <= INC;
		ptr_cnt_op <= INC;
		state      <= S_IDLE;
	 elsif state = S_PTR_DEC then
		pc_op      <= INC;
		ptr_cnt_op <= DEC;
		state      <= S_IDLE;
	 elsif state = S_DAT_INC then
		alu_op     <= INC;
		DATA_EN    <= '1'; --read from ram
		state      <= S_DAT_SAVE;
	 elsif state = S_DAT_DEC then
		alu_op     <= DEC;
		DATA_EN    <= '1'; --read from ram
		state      <= S_DAT_SAVE;
	 elsif state = S_DAT_SAVE then
		pc_op      <= INC;
		
		DATA_EN    <= '1'; --enable ram
		DATA_WE    <= '1'; --write to ram
		
		state      <= S_IDLE;
	 elsif state = S_OUT_RAM then
		DATA_EN    <= '1'; --read from ram
		state      <= S_OUT;
	 elsif state = S_OUT then
		if OUT_BUSY = '0' then
			OUT_WE  <= '1';
			pc_op   <= INC;
			state   <= S_IDLE;
		end if;
	 elsif state = S_IN then
		IN_REQ <= '1';
		if IN_VLD = '1' then
			DATA_WE <= '1'; --write to ram
			DATA_EN <= '1';
			pc_op   <= INC;
			alu_op  <= PASS_IN;
			state   <= S_IN_RAM;
		end if;
	 elsif state = S_IN_RAM then
			pc_op   <= NOP;
			state   <= S_IDLE;
	 elsif state = S_LOOP_S then
		state      <= S_LOOP_S_IF;
	 elsif state = S_LOOP_S_IF then
		DATA_EN    <= '0'; --read from ram
		if conv_integer(DATA_RDATA) = 0 then
			pc_op       <= INC;
			state       <= S_F_LOOP_END_R;
		else
			pc_op       <= INC;
			ras_op      <= PUSH;
			state       <= S_IDLE;
		end if;
	 elsif state = S_F_LOOP_END then
		pc_op    <= INC;
		state    <= S_F_LOOP_END_R;
		CODE_EN  <= '1';
		
		if conv_integer(CODE_DATA) = character'pos(']') then
			loop_cnt_op <= DEC;
			
			if conv_integer(loop_count) = 1 then
				pc_op       <= NOP;
				CODE_EN     <= '0';
				state       <= S_DECODE;
			end if;
		elsif conv_integer(CODE_DATA) = character'pos('[') then
			loop_cnt_op <= INC;
		end if;
	 elsif state = S_F_LOOP_END_R then
		pc_op       <= NOP;
		loop_cnt_op <= NOP;
		state       <= S_F_LOOP_END;
	 elsif state = S_LOOP_E then
		DATA_EN    <= '1'; --read from ram
		state      <= S_LOOP_E_IF;
	 elsif state = S_LOOP_E_IF then
		DATA_EN    <= '0'; --read from ram
		if conv_integer(DATA_RDATA) = 0 then
			pc_op       <= INC;
			ras_op      <= DROP;
			state       <= S_IDLE;
		else
			ras_op      <= POP;
			state       <= S_DIRECT;
		end if;
	  elsif state = S_DIRECT then
		pc_op       <= DIRECT;
		ras_op      <= NOP;
		state       <= S_IDLE;
	 end if;
	end if;
  end if;
end process;

OUT_DATA <= DATA_RDATA;
 
end behavioral;
 
