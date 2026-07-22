library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_MISC.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.math_real.all;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;

entity BLSuppressor_a is
  generic (
    kNumSample        : integer := 4;
    kWidthAdcData     : integer := 10;
    kNumFsModeWords   : integer := 256;
    
    kPreSamples       : integer range 1 to 15 := 1;  
    kPostSamples      : integer range 0 to 15 := 1;  
    
    enDEBUG           : boolean := false
  );
  port (
    srst              : in  std_logic;
    clk               : in  std_logic;
    enUnit            : in  std_logic;
    polarityIn        : in  std_logic;
    thresholdIn       : in  std_logic_vector(kWidthAdcData-1 downto 0);

    -- Data In  --
    validIn           : in  std_logic;
    dIn               : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);

    -- Data Out  --
    validOut          : out std_logic; 
    dOut              : out std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    typeOut           : out std_logic_vector(kWidthAdcSFType-1 downto 0) 
  );
end BLSuppressor_a;

architecture RTL of BLSuppressor_a is

  constant kNegPulse  : std_logic := '0';
  constant kPosPulse  : std_logic := '1';
  constant kZero      : std_logic_vector(kWidthAdcData-1 downto 0) := (others => '0');

  -- RAM (Ring Buffer) Definition
  -- kRamDepth=128 is highly efficient for Distributed RAM (LUTRAM) in Vivado
  constant kRamDepth  : integer := 128; 
  type t_ram is array (0 to kRamDepth-1) of std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
  signal ram_bank     : t_ram := (others => (others => '0'));

  signal addr_w       : integer range 0 to kRamDepth-1 := 0;
  signal addr_r       : integer range 0 to kRamDepth-1 := 0;

  type IntDataArray is array (integer range 0 to kNumSample-1) of std_logic_vector(kWidthAdcData-1 downto 0);
  signal adc_data     : IntDataArray;

  signal judge_flag   : std_logic_vector(kNumSample-1 downto 0);
  signal pulse_detect : std_logic;

  -- Logic Control Flags & Counters
  signal is_active    : std_logic := '0';
  signal post_counter : integer range 0 to 63 := 0;

  constant kWidthCounter : integer := integer(ceil(log2(real(kNumFsModeWords))));
  signal fs_counter      : unsigned(kWidthCounter-1 downto 0) := (others => '0');
  signal size_count      : unsigned(kWidthCounter-1 downto 0) := (others => '0');

  -- Pipeline Registers
  signal reg_valid_out : std_logic;
  signal reg_dout      : std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
  signal reg_type_out  : std_logic_vector(kWidthAdcSFType-1 downto 0);

begin

  -- Output Assignments
  validOut <= reg_valid_out;
  dOut     <= reg_dout;
  typeOut  <= reg_type_out;

  -- Input Data Breakdown
  gen_breakdown : for i in 0 to kNumSample-1 generate
    adc_data(i) <= dIn((i+1)*kWidthAdcData-1 downto i*kWidthAdcData);
  end generate;

  -- Threshold Judgment
  gen_judge : process(adc_data, polarityIn, thresholdIn)
  begin
    for i in 0 to kNumSample-1 loop
      if(polarityIn = kPosPulse) then
        if(unsigned(adc_data(i)) >= unsigned(thresholdIn) and adc_data(i) /= kZero) then
          judge_flag(i) <= '1';
        else
          judge_flag(i) <= '0';
        end if;
      else
        if(unsigned(adc_data(i)) <= unsigned(thresholdIn) and adc_data(i) /= kZero) then
          judge_flag(i) <= '1';
        else
          judge_flag(i) <= '0';
        end if;
      end if;
    end loop;
  end process;

  pulse_detect <= or_reduce(judge_flag);

  -- Main Process (Ring Buffer & Control Logic)
  u_main : process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        is_active     <= '0';
        addr_w        <= 0;
        addr_r        <= 0;
        post_counter  <= 0;
        size_count    <= (others => '0');
        fs_counter    <= (others => '0');
        reg_valid_out <= '0';
        reg_dout      <= (others => '0');
        reg_type_out  <= (others => '0');
      else
        reg_valid_out <= '0'; 

        if enUnit = '1' then
          -- Process only when input data is valid
          if validIn = '1' then
            
            -------------------------------------------------
            -- 1. RAM Write (Continuous Ring Buffer)
            -------------------------------------------------
            ram_bank(addr_w) <= dIn;
            if addr_w = kRamDepth - 1 then
              addr_w <= 0;
            else
              addr_w <= addr_w + 1;
            end if;

            -------------------------------------------------
            -- 2. Read & Output Control Logic
            -------------------------------------------------
            if is_active = '0' then
              -- [IDLE Phase] Waiting for pulse
              if pulse_detect = '1' then
                is_active     <= '1';
                reg_valid_out <= '1';
                reg_type_out  <= kCTypeSfHead;
                reg_dout      <= (others => '1'); -- Header dummy data (FFFF)
                
                post_counter  <= kPreSamples + kPostSamples + 1;
                size_count    <= (others => '0');

                -- Set read pointer to the past (Pre-trigger)
                if addr_w >= kPreSamples then
                  addr_r <= addr_w - kPreSamples;
                else
                  addr_r <= kRamDepth - (kPreSamples - addr_w);
                end if;
              end if;

            else
              -- [ACTIVE Phase] Sending Payload or Trailer
              
              -- Handle re-trigger seamlessly
              if pulse_detect = '1' then
                post_counter <= kPreSamples + kPostSamples + 1;
              end if;

              -- If counter is running OR pulse just arrived, keep sending Payload
              if post_counter > 0 or pulse_detect = '1' then
                reg_valid_out <= '1';
                reg_type_out  <= kCTypeSfPayload;
                reg_dout      <= ram_bank(addr_r); -- Asynchronous read from RAM
                size_count    <= size_count + 1;

                -- Increment read pointer safely
                if addr_r = kRamDepth - 1 then
                  addr_r <= 0;
                else
                  addr_r <= addr_r + 1;
                end if;

                -- Decrement counter only if no new pulse is detected
                if pulse_detect = '0' then
                  post_counter <= post_counter - 1;
                end if;

              else
                -- [TRAILER Phase] Counter is 0, close the event
                reg_valid_out <= '1';
                reg_type_out  <= kCTypeSfTrail;
                reg_dout      <= std_logic_vector(resize(size_count, reg_dout'length));
                
                is_active     <= '0'; -- Return to IDLE
              end if;
              
            end if; -- is_active
            
          end if; -- validIn = '1'

        else
          -------------------------------------------------
          -- 3. Streaming Mode (enUnit = '0')
          -------------------------------------------------
          if validIn = '1' then
            reg_valid_out <= '1';
            reg_dout      <= dIn;
            fs_counter    <= fs_counter + 1;

            if fs_counter = 0 then
              reg_type_out <= kCTypeSfHead;
            else
              reg_type_out <= kCTypeSfPayload;
            end if;

            if fs_counter = kNumFsModeWords - 1 then
              fs_counter <= (others => '0');
            end if;
          end if;
        end if; -- enUnit

      end if;
    end if;
  end process;

end RTL;