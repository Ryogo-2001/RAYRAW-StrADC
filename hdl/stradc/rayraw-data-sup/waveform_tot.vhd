-- File: waveform_tot.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;

entity waveform_tot is
  generic (
    kNumSample    : integer := 4;
    kWidthAdcData : integer := 10;
    kWidthToT     : integer := 32 -- ToT count bit
  );
  port (
    clk           : in  std_logic;
    srst          : in  std_logic;

    -- ToT th
    thresholdIn   : in  std_logic_vector(kWidthAdcData-1 downto 0);

    -- Data In --
    validIn       : in  std_logic;
    dIn           : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    typeIn        : in  std_logic_vector(kWidthAdcSFType-1 downto 0);

    -- Data Out --
    validOut      : out std_logic;
    totOut        : out std_logic_vector(kWidthToT-1 downto 0)
  );
end waveform_tot;

architecture Behavioral of waveform_tot is

  type IntDataArray is array (0 to kNumSample-1) of unsigned(kWidthAdcData-1 downto 0);
  signal adc_data : IntDataArray;

  -- tot counter
  signal reg_tot  : unsigned(kWidthToT-1 downto 0) := (others => '0');

begin

    --40bit ->10bit 10bit 10bit 10bit
  gen_unpack : for i in 0 to kNumSample-1 generate
    adc_data(i) <= unsigned(dIn((i+1)*kWidthAdcData-1 downto i*kWidthAdcData));
  end generate;
 --main
  u_tot : process(clk)
    variable var_count : unsigned(kWidthToT-1 downto 0);
    variable var_th    : unsigned(kWidthAdcData-1 downto 0);
  begin
    if rising_edge(clk) then
      if srst = '1' then
        reg_tot  <= (others => '0');
        validOut <= '0';
        totOut   <= (others => '0');
      else
        validOut <= '0';

        if validIn = '1' then
          
          if typeIn = kCTypeSfHead then
            -- trset tot count
            reg_tot <= (others => '0');

          elsif typeIn = kCTypeSfPayload then
            var_count := (others => '0');
            var_th    := unsigned(thresholdIn);
            -- main main
            for i in 0 to kNumSample-1 loop
              -- if over th count up
              if adc_data(i) >= var_th then
                var_count := var_count + 1;
              end if;
            end loop;

          
            reg_tot <= reg_tot + var_count;

          elsif typeIn = kCTypeSfTrail then
            -- output tot
            totOut   <= std_logic_vector(reg_tot);
            validOut <= '1'; 
          end if;

        end if;
      end if;
    end if;
  end process;

end Behavioral;