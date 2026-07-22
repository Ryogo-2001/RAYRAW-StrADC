-- File: DataSelector.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;

entity DataSelector is
  generic (
    kNumSample     : integer := 4;
    kWidthAdcData  : integer := 10;
    kWidthIntegral : integer := 32;
    kMaxBufWords   : integer := 256
  );
  port (
    clk            : in  std_logic;
    srst           : in  std_logic;

    -- data in
    raw_validIn    : in  std_logic;
    raw_dIn        : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    raw_typeIn     : in  std_logic_vector(kWidthAdcSFType-1 downto 0);

    -- data in (each module)
    intg_val       : in  std_logic_vector(kWidthIntegral-1 downto 0);
    peak_val       : in  std_logic_vector(kWidthAdcData-1 downto 0);
    tot_val        : in  std_logic_vector(kWidthIntegral-1 downto 0);
    isSat          : in  std_logic;
    isPileup       : in  std_logic;
    pileup_valid   : in  std_logic;

    -- data out
    validOut       : out std_logic;
    dOut           : out std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    typeOut        : out std_logic_vector(kWidthAdcSFType-1 downto 0)
  );
end DataSelector;

architecture Behavioral of DataSelector is

  constant kWidthBus : integer := kNumSample * kWidthAdcData;

  -- memory
  type t_data_buf is array (0 to kMaxBufWords-1) of std_logic_vector(kWidthBus-1 downto 0);
  type t_type_buf is array (0 to kMaxBufWords-1) of std_logic_vector(kWidthAdcSFType-1 downto 0);
  
  signal buf_d : t_data_buf;
  signal buf_t : t_type_buf;
  
  signal wr_ptr : integer range 0 to kMaxBufWords-1 := 0;
  signal rd_ptr : integer range 0 to kMaxBufWords-1 := 0;

  -- flag
  signal flag_send_raw  : std_logic := '0';
  signal flag_send_sum1 : std_logic := '0';
  signal flag_send_sum2 : std_logic := '0';

  -- latch
  signal reg_intg : std_logic_vector(kWidthIntegral-1 downto 0);
  signal reg_peak : std_logic_vector(kWidthAdcData-1 downto 0);
  signal reg_tot  : std_logic_vector(kWidthIntegral-1 downto 0);

begin

  --buffer
  u_write : process(clk)
  begin
    if rising_edge(clk) then
      if raw_validIn = '1' then
        if raw_typeIn = kCTypeSfHead then
          -- When the header arrives, reset the pointer and write.
          buf_d(0) <= raw_dIn;
          buf_t(0) <= raw_typeIn;
          wr_ptr   <= 1;
        else
          -- write
          buf_d(wr_ptr) <= raw_dIn;
          buf_t(wr_ptr) <= raw_typeIn;
          wr_ptr <= wr_ptr + 1;
        end if;
      end if;
    end if;
  end process;

  --flag
  u_read : process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        flag_send_raw  <= '0';
        flag_send_sum1 <= '0';
        flag_send_sum2 <= '0';
        validOut       <= '0';
      else
        validOut <= '0'; 

        -- Judgment part
        if pileup_valid = '1' then
          if (isSat = '1') or (isPileup = '1') then
            -- saturate or pileup flag->1
            flag_send_raw <= '1';
            rd_ptr        <= 0;
          else
            flag_send_sum1 <= '1';
            reg_intg       <= intg_val;
            reg_peak       <= peak_val;
            reg_tot        <= tot_val;
          end if;
        end if;

        --Out
        
        -- send integral
        if flag_send_sum1 = '1' then
          flag_send_sum1 <= '0'; 
          flag_send_sum2 <= '1'; 
          
          validOut <= '1';
          typeOut  <= kCTypeSfPayload;
          dOut     <= reg_intg & x"00"; -- 32bit + 8bit = 40bit
        
        -- send tot
        elsif flag_send_sum2 = '1' then
          flag_send_sum2 <= '0'; 
          
          validOut <= '1';
          typeOut  <= kCTypeSfTrail;
          dOut     <= reg_tot(29 downto 0) & reg_peak; -- 30bit + 10bit = 40bit

        -- send RAW data
        elsif flag_send_raw = '1' then
          validOut <= '1';
          typeOut  <= buf_t(rd_ptr);
          dOut     <= buf_d(rd_ptr);
          
          if buf_t(rd_ptr) = kCTypeSfTrail then
            flag_send_raw <= '0'; -- T end rail
          else
            rd_ptr <= rd_ptr + 1;
          end if;
        end if;

      end if;
    end if;
  end process;

end Behavioral;