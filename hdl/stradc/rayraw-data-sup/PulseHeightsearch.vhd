-- File: PulseHeightsearch.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;

entity PulseHeightSearch is
  generic (
    kNumSample    : integer := 4;
    kWidthAdcData : integer := 10
  );
  port (
    clk           : in  std_logic;
    srst          : in  std_logic;

    -- Data In --
    validIn       : in  std_logic;
    dIn           : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    typeIn        : in  std_logic_vector(kWidthAdcSFType-1 downto 0);

    -- Data Out --
    validOut      : out std_logic;
    peakOut       : out std_logic_vector(kWidthAdcData-1 downto 0)
  );
end PulseHeightSearch;

architecture Behavioral of PulseHeightSearch is

  type IntDataArray is array (0 to kNumSample-1) of unsigned(kWidthAdcData-1 downto 0);
  signal adc_data : IntDataArray;

  -- reg
  signal reg_peak : unsigned(kWidthAdcData-1 downto 0) := (others => '0');

begin


  gen_unpack : for i in 0 to kNumSample-1 generate
    adc_data(i) <= unsigned(dIn((i+1)*kWidthAdcData-1 downto i*kWidthAdcData));
  end generate;

  u_peak : process(clk)
    variable var_max : unsigned(kWidthAdcData-1 downto 0);
  begin
    if rising_edge(clk) then
      if srst = '1' then
        reg_peak <= (others => '0');
        validOut <= '0';
        peakOut  <= (others => '0');
      else
        validOut <= '0';

        if validIn = '1' then
          
          if typeIn = kCTypeSfHead then
            --reset reg
            reg_peak <= (others => '0');

          elsif typeIn = kCTypeSfPayload then
            -- start
            var_max := reg_peak;

            for i in 0 to kNumSample-1 loop
              if adc_data(i) > var_max then
                var_max := adc_data(i);
              end if;
            end loop;

            
            reg_peak <= var_max;

          elsif typeIn = kCTypeSfTrail then
        
            peakOut  <= std_logic_vector(reg_peak);
            validOut <= '1'; 
          end if;

        end if;
      end if;
    end if;
  end process;

end Behavioral;