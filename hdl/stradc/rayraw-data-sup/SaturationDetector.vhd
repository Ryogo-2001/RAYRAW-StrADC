-- File: SaturationDetector.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;

entity SaturationDetector is
  generic (
    kNumSample    : integer := 4;
    kWidthAdcData : integer := 10;
    kSatValue     : integer := 1023;
    kValidNumSample : integer := 3
  );
  port (
    clk           : in  std_logic;
    srst          : in  std_logic;
    polarityIn    : in  std_logic;

    -- Data In --
    validIn       : in  std_logic;
    dIn           : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    typeIn        : in  std_logic_vector(kWidthAdcSFType-1 downto 0);

    -- Data Out --
    validOut      : out std_logic;
    isSaturation  : out std_logic
  );
end SaturationDetector;

architecture Behavioral of SaturationDetector is

  type IntDataArray is array (0 to kNumSample-1) of unsigned(kWidthAdcData-1 downto 0);
  signal adc_data : IntDataArray;

  signal reg_sat  : std_logic := '0';

  constant kSatValueNeg : integer := 2**kWidthAdcData - 1 - kSatValue;

begin

  gen_unpack : for i in 0 to kNumSample-1 generate
    adc_data(i) <= unsigned(dIn((i+1)*kWidthAdcData-1 downto i*kWidthAdcData));
  end generate;

  u_detect : process(clk)
    variable var_sat : std_logic;
  begin
    if rising_edge(clk) then
      if srst = '1' then
        reg_sat      <= '0';
        validOut     <= '0';
        isSaturation <= '0';
      else
        validOut <= '0';

        if validIn = '1' then
          if typeIn = kCTypeSfHead then
            reg_sat <= '0';

          elsif typeIn = kCTypeSfPayload then
            var_sat := '0';
            for i in 0 to kValidNumSample-1 loop
              if polarityIn = '1' then
                if adc_data(i) >= to_unsigned(kSatValue, kWidthAdcData) then
                  var_sat := '1';
                end if;
              else
                if adc_data(i) <= to_unsigned(kSatValueNeg, kWidthAdcData) then
                  var_sat := '1';
                end if;
              end if;
            end loop;

            if var_sat = '1' then
              reg_sat <= '1';
            end if;

          elsif typeIn = kCTypeSfTrail then
            isSaturation <= reg_sat;
            validOut     <= '1'; 
          end if;
        end if;
      end if;
    end if;
  end process;

end Behavioral;