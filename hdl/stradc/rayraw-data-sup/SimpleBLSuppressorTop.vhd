-- File: SimpleBLSuppressorTop.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defADC.all;
use mylib.defDelimiter.all;

entity SimpleBLSuppressorTop is
  generic (
    kNumSample        : integer := 4;
    kWidthAdcData     : integer := 10;
    kWidthIntegral    : integer := 32;
    kNumFsModeWords   : integer := 256;

    kPreSamples       : integer range 1 to 15 := 2;
    kPostSamples      : integer range 0 to 15 := 4;

    kSatValue         : integer := 1023;
    kLutDepth         : integer := 64;
    kMaxBufWords      : integer := 256;

    enDEBUG           : boolean := false
  );
  port (
    srst              : in  std_logic;
    clk               : in  std_logic;

    -- BLSuppressor --
    enUnit            : in  std_logic;
    polarityIn        : in  std_logic;
    thresholdIn       : in  std_logic_vector(kWidthAdcData-1 downto 0);
    baselineIn        : in  std_logic_vector(kWidthAdcData-1 downto 0);

    -- LACCP / Delimiter --
    hbCount           : in  std_logic_vector(kWidthStrHbc-1 downto 0);
    hbfNumber         : in  std_logic_vector(kWidthStrHbf-1 downto 0);
    signBit           : in  std_logic;
    flagsIn           : in  std_logic_vector(kWidthDelimiterFlag-1 downto 0);

    -- Data In --
    validIn           : in  std_logic;
    dIn               : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);

    -- Data Out (64bit, HBD-framed) --
    validOut          : out std_logic;
    dOut              : out std_logic_vector(63 downto 0)
  );
end SimpleBLSuppressorTop;

architecture Behavioral of SimpleBLSuppressorTop is

  -- HBD --
  signal hbd_valid       : std_logic;
  signal hbd_data        : std_logic_vector(63 downto 0);

  -- BLSuppressor --
  signal supp_validOut   : std_logic;
  signal supp_dOut       : std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
  signal supp_typeOut    : std_logic_vector(kWidthAdcSFType-1 downto 0);

  -- WaveformIntegrator --
  signal intg_validOut   : std_logic;
  signal intg_dOut       : std_logic_vector(kWidthIntegral-1 downto 0);

  -- SaturationDetector --
  signal sat_validOut    : std_logic;
  signal sat_dOut        : std_logic;

  -- PulseHeightSearch --
  signal peak_validOut   : std_logic;
  signal peak_dOut       : std_logic_vector(kWidthAdcData-1 downto 0);

  -- waveform_tot  --
  signal tot_validOut    : std_logic;
  signal tot_dOut        : std_logic_vector(kWidthIntegral-1 downto 0);

  -- pileupDetector --
  signal pileup_validOut : std_logic;
  signal pileup_dOut     : std_logic;

begin

  -- HBD Generator
  u_delimiter_gen : entity mylib.DelimiterGenerator
    generic map (
      enDEBUG => enDEBUG
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

  -- BLSuppressor
  u_suppressor : entity mylib.BLSuppressor_bram
    generic map (
      kNumSample      => kNumSample,
      kWidthAdcData   => kWidthAdcData,
      kNumFsModeWords => kNumFsModeWords,
      kPreSamples     => kPreSamples,
      kPostSamples    => kPostSamples,
      enDEBUG         => enDEBUG
    )
    port map (
      srst        => srst,
      clk         => clk,
      enUnit      => enUnit,
      polarityIn  => polarityIn,
      thresholdIn => thresholdIn,
      hbCount     => hbCount,
      validIn     => validIn,
      dIn         => dIn,
      validOut    => supp_validOut,
      dOut        => supp_dOut,
      typeOut     => supp_typeOut
    );

  -- WaveformIntegrator
  u_integrator : entity mylib.WaveformIntegrator
    generic map (
      kNumSample     => kNumSample,
      kWidthAdcData  => kWidthAdcData,
      kWidthIntegral => kWidthIntegral
    )
    port map (
      clk         => clk,
      srst        => srst,
      baselineIn  => baselineIn,
      validIn     => supp_validOut,
      dIn         => supp_dOut,
      typeIn      => supp_typeOut,
      validOut    => intg_validOut,
      integralOut => intg_dOut
    );

  -- SaturationDetector
  u_saturation : entity mylib.SaturationDetector
    generic map (
      kNumSample    => kNumSample,
      kWidthAdcData => kWidthAdcData,
      kSatValue     => kSatValue
    )
    port map (
      clk          => clk,
      srst         => srst,
      validIn      => supp_validOut,
      dIn          => supp_dOut,
      typeIn       => supp_typeOut,
      validOut     => sat_validOut,
      isSaturation => sat_dOut
    );

  -- PulseHeightSearch
  u_peak : entity mylib.PulseHeightSearch
    generic map (
      kNumSample    => kNumSample,
      kWidthAdcData => kWidthAdcData
    )
    port map (
      clk      => clk,
      srst     => srst,
      validIn  => supp_validOut,
      dIn      => supp_dOut,
      typeIn   => supp_typeOut,
      validOut => peak_validOut,
      peakOut  => peak_dOut
    );

  -- waveform_tot
  u_tot : entity mylib.waveform_tot
    generic map (
      kNumSample    => kNumSample,
      kWidthAdcData => kWidthAdcData,
      kWidthToT     => kWidthIntegral
    )
    port map (
      clk         => clk,
      srst        => srst,
      thresholdIn => thresholdIn,
      validIn     => supp_validOut,
      dIn         => supp_dOut,
      typeIn      => supp_typeOut,
      validOut    => tot_validOut,
      totOut      => tot_dOut
    );

  -- pileupDetector
  u_pileup : entity mylib.pileupDetector
    generic map (
      kWidthAdcData => kWidthAdcData,
      kWidthToT     => kWidthIntegral,
      kLutDepth     => kLutDepth
    )
    port map (
      clk      => clk,
      srst     => srst,
      validIn  => peak_validOut,
      peakIn   => peak_dOut,
      totIn    => tot_dOut,
      validOut => pileup_validOut,
      isPileup => pileup_dOut
    );

  -- DataSelector
  u_selector : entity mylib.DataSelector
    generic map (
      kNumSample     => kNumSample,
      kWidthAdcData  => kWidthAdcData,
      kWidthIntegral => kWidthIntegral,
      kMaxBufWords   => kMaxBufWords
    )
    port map (
      clk            => clk,
      srst           => srst,

      -- data in (ADC)
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
      validOut       => validOut,
      dOut           => dOut
    );

end Behavioral;
