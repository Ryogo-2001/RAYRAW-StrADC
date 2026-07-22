-- File: pileupDetector.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;

entity pileupDetector is
  generic (
    kWidthAdcData : integer := 10;
    kWidthToT     : integer := 32;
    -- LUT
    kLutDepth     : integer := 64 
  );
  port (
    clk           : in  std_logic;
    srst          : in  std_logic;

    -- Data In (PulseHeight,ToT) --
    validIn       : in  std_logic;
    peakIn        : in  std_logic_vector(kWidthAdcData-1 downto 0);
    totIn         : in  std_logic_vector(kWidthToT-1 downto 0);

    -- Data Out --
    validOut      : out std_logic;
    isPileup      : out std_logic
  );
end pileupDetector;

-- LUT
architecture Behavioral of pileupDetector is

  type t_lut_row is record
    minADC : integer;
    maxADC : integer;
  end record;

  
  type t_lut_array is array (0 to kLutDepth-1) of t_lut_row;

  
  -- ToT => (minADC =>, maxADC => )
  constant kPileupLUT : t_lut_array := (
    1  => (minADC => 524,  maxADC => 544),
    2  => (minADC => 526,  maxADC => 546),
    3  => (minADC => 529,  maxADC => 549),
    4  => (minADC => 524,  maxADC => 544),
    5  => (minADC => 531,  maxADC => 551),
    6  => (minADC => 531,  maxADC => 551),
    7  => (minADC => 532,  maxADC => 552),
    8  => (minADC => 539,  maxADC => 559),
    9  => (minADC => 544,  maxADC => 564),
    10 => (minADC => 554,  maxADC => 574),
    11 => (minADC => 547,  maxADC => 597),
    12 => (minADC => 564,  maxADC => 604),
    13 => (minADC => 571,  maxADC => 631),
    14 => (minADC => 589,  maxADC => 651),
    15 => (minADC => 601,  maxADC => 693),
    16 => (minADC => 627,  maxADC => 739),
    17 => (minADC => 656,  maxADC => 800),
    18 => (minADC => 702,  maxADC => 870),
    19 => (minADC => 769,  maxADC => 928),
    20 => (minADC => 845,  maxADC => 916),
    -- No limit -> 0~1023
    -- All abnormality -> 1023~0
    others => (minADC => 1023, maxADC => 0)
  );

begin

  u_judge : process(clk)
    variable var_tot  : integer;
    variable var_peak : integer;
  begin
    if rising_edge(clk) then
      if srst = '1' then
        validOut <= '0';
        isPileup <= '0';
      else
        validOut <= '0';

        if validIn = '1' then
          validOut <= '1'; 

          -- ToT, Peak-> integer
          var_tot  := to_integer(unsigned(totIn));
          var_peak := to_integer(unsigned(peakIn));
          -- Exclude values ​​where ToT exceeds the table size (kLutDepth)
          if var_tot >= kLutDepth then
            isPileup <= '1';
          else
            -- main (LUT)
            if (var_peak >= kPileupLUT(var_tot).minADC) and 
               (var_peak <= kPileupLUT(var_tot).maxADC) then
              isPileup <= '0'; -- normal pulse
            else
              isPileup <= '1'; -- Pile-up pulse
            end if;
          end if;

        end if;
      end if;
    end if;
  end process;

end Behavioral;