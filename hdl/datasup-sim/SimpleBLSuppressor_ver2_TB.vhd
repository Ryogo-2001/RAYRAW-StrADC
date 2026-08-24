library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use std.textio.all;

library mylib;
use mylib.defYaenamiAdc.all;
use mylib.defADC.all;
use mylib.simpleblsuppressor_simset.all;
use mylib.VhdlSimSet.all;
use mylib.defDataBusAbst.all;-- HBD
use mylib.defDelimiter.all;-- HBD
use mylib.defLaccp.all;-- HBD

entity SimpleBLSuppressor_ver2_TB is
end SimpleBLSuppressor_ver2_TB;

architecture Behavioral of SimpleBLSuppressor_ver2_TB is

  constant kNumSample     : integer := 4;
  constant kAdcWidthData     : integer := 10;
  constant kWidthIntegral : integer := 32; 

  signal clk          : std_logic;
  signal srst         : std_logic;
  
  -- signal in
  signal validIn      : std_logic;
  signal dIn          : std_logic_vector(kNumSample*kAdcWidthData-1 downto 0);

  -- hbCount
  signal hbCount       : std_logic_vector(15 downto 0) := (others => '0');
  signal tb_hb_counter : unsigned(15 downto 0) := (others => '0');
  
  -- BLSupressor
  signal supp_validOut : std_logic;
  signal supp_dOut     : std_logic_vector(kNumSample*kAdcWidthData-1 downto 0);
  signal supp_typeOut  : std_logic_vector(kWidthAdcSFType-1 downto 0);

  -- integral signal
  signal intg_validOut : std_logic;
  signal intg_dOut : std_logic_vector(kWidthIntegral-1 downto 0);

  -- saturation
  signal sat_validOut  : std_logic;
  signal sat_dOut     : std_logic;

  -- pulse height signal
  signal peak_validOut : std_logic;
  signal peak_dOut     : std_logic_vector(kAdcWidthData-1 downto 0);
  
  -- tot logic
  signal tot_validOut : std_logic;
  signal tot_dOut      : std_logic_vector(kWidthIntegral-1 downto 0);

  -- pile up Detection
  signal pileup_validOut : std_logic;
  signal pileup_dOut : std_logic;

  -- DelimiterGenerator
  signal flagsIn         : std_logic_vector(kWidthDelimiterFlag-1 downto 0) := (others => '0');
  signal hbfNumber       : std_logic_vector(kWidthStrHbf-1 downto 0) := std_logic_vector(to_unsigned(1, kWidthStrHbf));
  signal signBit         : std_logic := '0';

  signal hbd_valid       : std_logic := '0';
  signal hbd_data        : std_logic_vector(63 downto 0) := (others => '0');
  
  -- dOut 64bit
  signal final_validOut  : std_logic;
  signal final_dOut      : std_logic_vector(63 downto 0);

  file in_file        : text;

begin

  -- HBD Generator
  u_delimiter_gen : entity mylib.DelimiterGenerator
    generic map (
      enDEBUG => false
    )
    port map (
      syncReset      => srst,
      clk            => clk,
      flagsIn        => flagsIn,
      hbCount        => hbCount,
      hbfNumber      => hbfNumber,
      signBit        => signBit,
      validDelimiter => hbd_valid,
      dOutDelimiter  => hbd_data
    );

  --hbCount 
  p_hb_counter : process(clk)
  begin
    if falling_edge(clk) then
      if srst = '1' then
        -- sim HBD start
        tb_hb_counter <= unsigned(kMaxHBCount) - 60; 
      else
        
        if tb_hb_counter = unsigned(kMaxHBCount) then
          tb_hb_counter <= (others => '0');
        else
          tb_hb_counter <= tb_hb_counter + 1;
        end if;
      end if;
    end if;
  end process;
  
  hbCount <= std_logic_vector(tb_hb_counter);

  -- clock read testpattern file 
  main : process
  begin
    srst <= '1';
    for i in 1 to 10 loop clock(clk); end loop;
    srst <= '0';
    for i in 1 to 2 loop clock(clk); end loop;

    --file_open(in_file, "C:/Users/ryogo/Vivado_project/RAYRAW-StrADC/test_pulse/normal/event_0002.txt", READ_MODE);
    file_open(in_file, "C:/Users/ryogo/Vivado_project/RAYRAW-StrADC/test_pulse/pile_up/event_0002.txt", READ_MODE);
    set_txt(in_file, clk, dIn, validIn);
    file_close(in_file);

    -- end
    for i in 1 to 1000 loop clock(clk); end loop;
    std.env.stop;
  end process;

  

  -- BLSuppressor
  u_dut : entity mylib.BLSuppressor_bram
    generic map(
      kNumSample      => kNumSample,
      kWidthAdcData   => kAdcWidthData,
      kNumFsModeWords => 256,
      kPreSamples     => 2,
      kPostSamples    => 4,
      enDEBUG         => false
    )
    port map(
      srst        => srst,
      clk         => clk,
      enUnit      => '1', 
      polarityIn  => '1',
      thresholdIn => std_logic_vector(to_unsigned(530, kAdcWidthData)),
      hbCount     => hbCount,
      validIn     => validIn,
      dIn         => dIn,
      validOut    => supp_validOut,
      dOut        => supp_dOut,
      typeOut     => supp_typeOut
    );

  -- waveformintegrator
  u_intg : entity mylib.WaveformIntegrator
    generic map(
      kNumSample     => kNumSample,
      kWidthAdcData  => kAdcWidthData,
      kWidthIntegral => kWidthIntegral
    )
    port map(
      clk          => clk,
      srst         => srst,
      baselineIn   => std_logic_vector(to_unsigned(500, kAdcWidthData)),
      validIn      => supp_validOut,
      dIn          => supp_dOut,
      typeIn       => supp_typeOut,
      validOut     => intg_validOut,
      integralOut  => intg_dOut
    );

  u_sat : entity mylib.SaturationDetector
    generic map(
      kNumSample    => kNumSample,
      kWidthAdcData => kAdcWidthData,
      kSatValue     => 910
    )
    port map(
      clk          => clk,
      srst         => srst,
      validIn      => supp_validOut,
      dIn          => supp_dOut,
      typeIn       => supp_typeOut,
      validOut     => sat_validOut,
      isSaturation => sat_dOut
    );

  u_peak : entity mylib.PulseHeightSearch
    generic map(
      kNumSample    => kNumSample,
      kWidthAdcData => kAdcWidthData
    )
    port map(
      clk          => clk,
      srst         => srst,
      validIn      => supp_validOut,
      dIn          => supp_dOut,
      typeIn       => supp_typeOut,
      validOut     => peak_validOut,
      peakOut      => peak_dOut
    );

  u_tot : entity mylib.waveform_tot
    generic map(
      kNumSample    => kNumSample,
      kWidthAdcData => kAdcWidthData,
      kWidthToT     => kWidthIntegral 
    )
    port map(
      clk          => clk,
      srst         => srst,
      thresholdIn  => std_logic_vector(to_unsigned(530, kAdcWidthData)),
      validIn      => supp_validOut,
      dIn          => supp_dOut,
      typeIn       => supp_typeOut,
      validOut     => tot_validOut,
      totOut       => tot_dOut
    );

  u_pileup : entity mylib.pileupDetector
    generic map(
      kWidthAdcData => kAdcWidthData,
      kWidthToT     => kWidthIntegral,
      kLutDepth     => 64
    )
    port map(
      clk          => clk,
      srst         => srst,
      validIn      => peak_validOut, 
      peakIn       => peak_dout,
      totIn        => tot_dOut,
      validOut     => pileup_validOut,
      isPileup     => pileup_dOut
    );

  -- DataSelector

  u_selector : entity mylib.DataSelector
    generic map(
      kNumSample     => kNumSample,
      kWidthAdcData  => kAdcWidthData,
      kWidthIntegral => kWidthIntegral,
      kMaxBufWords   => 256
    )
    port map(
      clk            => clk,
      srst           => srst,

      -- data in
      raw_validIn    => supp_validOut,
      raw_dIn        => supp_dOut,
      raw_typeIn     => supp_typeOut,
      intg_val       => intg_dOut,
      peak_val       => peak_dOut,
      tot_val        => tot_dOut,
      isSat          => sat_dOut,
      isPileup       => pileup_dOut,
      pileup_valid   => pileup_validOut, 

      -- HBD in
      validDelimiter => hbd_valid,
      dInDelimiter   => hbd_data,

      -- dOut (64bit)
      validOut       => final_validOut,
      dOut           => final_dOut
    );

end Behavioral;