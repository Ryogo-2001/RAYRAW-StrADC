-- File: BLSuppressor_bram.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_MISC.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.math_real.all;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;

entity BLSuppressor_bram is
  generic (
    kNumSample        : integer := 4;
    kWidthAdcData     : integer := 10;
    kNumFsModeWords   : integer := 256;
    
    kPreSamples       : integer range 1 to 15 := 2;  
    kPostSamples      : integer range 0 to 15 := 4;  
    kMaxPayloadWords  : integer := 254;
    
    enDEBUG           : boolean := false
  );
  port (
    srst              : in  std_logic;
    clk               : in  std_logic;
    enUnit            : in  std_logic;
    polarityIn        : in  std_logic;
    thresholdIn       : in  std_logic_vector(kWidthAdcData-1 downto 0);

    -- hbcount
    hbCount           : in std_logic_vector(15 downto 0);

    -- Data In  --
    validIn           : in  std_logic;
    dIn               : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);

    -- Data Out  --
    validOut          : out std_logic; 
    dOut              : out std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    typeOut           : out std_logic_vector(kWidthAdcSFType-1 downto 0) 
  );
end BLSuppressor_bram;

architecture BRAM_Based of BLSuppressor_bram is

  constant kNegPulse  : std_logic := '0';
  constant kPosPulse  : std_logic := '1';
  constant kZero      : std_logic_vector(kWidthAdcData-1 downto 0) := (others => '0');

  -- RAM (Ring Buffer) 
  -- Depth 1024
  constant kRamDepth  : integer := 1024; 
  type t_ram is array (0 to kRamDepth-1) of std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
  signal ram_bank     : t_ram := (others => (others => '0'));

  signal addr_w       : integer range 0 to kRamDepth-1 := 0; --write point 
  signal addr_r       : integer range 0 to kRamDepth-1 := 0; --read point
  signal ram_dout     : std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);

  type IntDataArray is array (integer range 0 to kNumSample-1) of std_logic_vector(kWidthAdcData-1 downto 0);
  signal adc_data     : IntDataArray;

  signal judge_flag   : std_logic_vector(kNumSample-1 downto 0);
  signal pulse_detect : std_logic;

  -- hbCount header
  type t_hb_delay is array (0 to 15) of std_logic_vector(15 downto 0);
  signal hb_delay_line : t_hb_delay := (others =>(others=> '0'));

  -- hbCount trailer
  signal prev_hbCount  : std_logic_vector(15 downto 0) := (others => '0');

  -- Logic Control Flags & Counters
  signal is_active    : std_logic := '0';
  signal post_counter : integer range 0 to 63 := 0;

  constant kWidthCounter : integer := integer(ceil(log2(real(kNumFsModeWords))));
  signal fs_counter      : unsigned(kWidthCounter-1 downto 0) := (others => '0');
  signal size_count      : integer range 0 to kMaxPayloadWords := 0;

  -- Pipeline Control Signals 
  signal ctrl_valid    : std_logic := '0';
  signal ctrl_use_ram  : std_logic := '0'; -- 1:Payload(BRAM), 0:Header/Trailer
  signal ctrl_dout     : std_logic_vector(kNumSample*kWidthAdcData-1 downto 0) := (others => '0');
  signal ctrl_type     : std_logic_vector(kWidthAdcSFType-1 downto 0) := (others => '0');

begin

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


  -- BRAM Process 

  u_bram : process(clk)
  begin
    if rising_edge(clk) then
      -- Write
      if enUnit = '1' and validIn = '1' then
        ram_bank(addr_w) <= dIn;

        -- hbCount Shift register
        hb_delay_line(0) <= hbCount;
        for i in 0 to 14 loop
          hb_delay_line(i+1) <= hb_delay_line(i);
        end loop;
      end if;
      
      -- Read 
      ram_dout <= ram_bank(addr_r);
    end if;
  end process;


  --Main 
  u_main : process(clk)
  begin
    if rising_edge(clk) then
      -- hbcount trail (trail time)
      -- prev_hbCount <= hbCount;
      -- hbcount trail (get last data time)
      if validIn = '1' then
        prev_hbCount <= hbCount;
      end if;

      if srst = '1' then
        is_active    <= '0';
        addr_w       <= 0;
        addr_r       <= 0;
        post_counter <= 0;
        size_count   <= 0;
        fs_counter   <= (others => '0');
        ctrl_valid   <= '0';
        ctrl_use_ram <= '0';
        ctrl_dout    <= (others => '0');
        ctrl_type    <= (others => '0');
      else
        ctrl_valid   <= '0'; 
        ctrl_use_ram <= '0'; -- not use BRAM

        if enUnit = '1' then
          if validIn = '1' then
            
            -- Write Pointer Update
            if addr_w = kRamDepth - 1 then
              addr_w <= 0;
            else
              addr_w <= addr_w + 1;
            end if;

            if is_active = '0' then
              -- IDLE
              if pulse_detect = '1' then
                is_active    <= '1';
                ctrl_valid   <= '1';
                ctrl_type    <= kCTypeSfHead;

                -- not use
                --ctrl_dout    <= (others => '1'); 
                -- hdcount main Header
                ctrl_dout    <= x"000000" & hb_delay_line(kPreSamples - 1);
                
                post_counter <= kPreSamples + kPostSamples + 1; 
                size_count   <= 0;

                if addr_w >= kPreSamples then
                  addr_r <= addr_w - kPreSamples;
                else
                  addr_r <= kRamDepth - (kPreSamples - addr_w);
                end if;
              end if;

            else
              -- ACTIVE
              if pulse_detect = '1' then
                post_counter <= kPreSamples + kPostSamples + 1;
              end if;

              if (post_counter > 0 or pulse_detect = '1') and size_count < kMaxPayloadWords then
                ctrl_valid   <= '1';
                ctrl_type    <= kCTypeSfPayload;
                ctrl_use_ram <= '1'; 
                size_count   <= size_count + 1;

                if addr_r = kRamDepth - 1 then
                  addr_r <= 0;
                else
                  addr_r <= addr_r + 1;
                end if;

                if pulse_detect = '0' then
                  post_counter <= post_counter - 1;
                end if;

              else
                -- TRAILER
                ctrl_valid <= '1';
                ctrl_type  <= kCTypeSfTrail;

                -- not use data size
                --ctrl_dout  <= std_logic_vector(resize(size_count, ctrl_dout'length));
                 -- hbCount main trailer
                 -- not use trail time
                 --ctrl_dout  <= x"000000" & hbCount;

                 -- hbCount last data time
                 ctrl_dout  <= x"000000" & prev_hbCount;


                is_active  <= '0'; 
              end if;
            end if; 
          end if; 

        else
          -- Streaming Mode
          if validIn = '1' then
            ctrl_valid <= '1';
            ctrl_dout  <= dIn;
            fs_counter <= fs_counter + 1;

            if fs_counter = 0 then
              ctrl_type <= kCTypeSfHead;
            else
              ctrl_type <= kCTypeSfPayload;
            end if;

            if fs_counter = kNumFsModeWords - 1 then
              fs_counter <= (others => '0');
            end if;
          end if;
        end if; 
      end if;
    end if;
  end process;


u_out : process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        validOut <= '0';
        typeOut  <= (others => '0');
        dOut     <= (others => '0');
      else
        validOut <= ctrl_valid;
        
        if ctrl_valid = '1' then
          typeOut  <= ctrl_type;
          
          if ctrl_use_ram = '1' then
            dOut <= ram_dout;  
          else
            dOut <= ctrl_dout; 
          end if;
        end if;
        
      end if;
    end if;
  end process;

end BRAM_Based;