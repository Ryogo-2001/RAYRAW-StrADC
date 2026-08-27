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

    -- time stamp--
    hbCount           : in  std_logic_vector(kWidthStrHbc-1 downto 0);

    -- Data In --
    validIn           : in  std_logic;
    dIn               : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);

    -- HBD in --
    validDelimiter    : in  std_logic;
    dInDelimiter      : in  std_logic_vector(63 downto 0);

    -- Data Out (64bit, HBD-framed) --
    validOut          : out std_logic;
    dOut              : out std_logic_vector(63 downto 0)
  );
end SimpleBLSuppressorTop;

architecture Behavioral of SimpleBLSuppressorTop is

  -- Debug ILA (only instantiated when enDEBUG=true, i.e. one selected channel).
  -- Probe widths assume kNumSample=4, kWidthAdcData=10 (the values ODPBlockADC
  -- instantiates this entity with); generate the ila_0 IP with matching widths:
  --   probe0 41b (dIn 40 + validIn 1), probe1 43b (supp_dOut 40 + supp_typeOut 2 + supp_validOut 1),
  --   probe2 2b (pileup_dOut + pileup_validOut), probe3 1b (sat_dOut), probe4 1b (validDelimiter),
  --   probe5 65b (dOut 64 + validOut 1)
  COMPONENT ila_0
    PORT (
      clk    : IN STD_LOGIC;
      probe0 : IN STD_LOGIC_VECTOR(40 DOWNTO 0);
      probe1 : IN STD_LOGIC_VECTOR(42 DOWNTO 0);
      probe2 : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
      probe3 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      probe4 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      probe5 : IN STD_LOGIC_VECTOR(64 DOWNTO 0)
    );
  END COMPONENT;

  -- Debug VIO: single button. While '1', dIn/validIn are overridden by a
  -- cycle-accurate replay of test_pulse/pile_up/event_0002.txt (the same
  -- vector datasup-sim/SimpleBLSuppressor_ver2_TB.vhd uses in simulation),
  -- instead of the real ADC stream. Generate vio_1 with:
  --   Input Probe Count=0, Output Probe Count=1, PROBE_OUT0 width=1
  COMPONENT vio_1
    PORT (
      clk        : IN STD_LOGIC;
      probe_out0 : OUT STD_LOGIC_VECTOR(0 DOWNTO 0)
    );
  END COMPONENT;

  constant kPlaybackDepth : integer := 185;
  type t_playback_rom is array (0 to kPlaybackDepth-1) of std_logic_vector(40 downto 0);
  -- packed as dIn(39:0) & validIn(0), one entry per clk cycle -- generated from
  -- test_pulse/pile_up/event_0002.txt (SEND/PAUSE expanded cycle-by-cycle,
  -- matching pkg_simpleblsuppressor_simset.vhd's set_txt procedure exactly)
  constant kPlaybackRom : t_playback_rom := (
    0 => std_logic_vector(to_unsigned(0, 41)),
    1 => std_logic_vector(to_unsigned(0, 41)),
    2 => std_logic_vector(to_unsigned(0, 41)),
    3 => std_logic_vector(to_unsigned(0, 41)),
    4 => std_logic_vector(to_unsigned(0, 41)),
    5 => std_logic_vector(to_unsigned(0, 41)),
    6 => std_logic_vector(to_unsigned(0, 41)),
    7 => std_logic_vector(to_unsigned(0, 41)),
    8 => std_logic_vector(to_unsigned(0, 41)),
    9 => std_logic_vector(to_unsigned(0, 41)),
    10 => std_logic_vector(to_unsigned(1068493821, 41)),
    11 => std_logic_vector(to_unsigned(0, 41)),
    12 => std_logic_vector(to_unsigned(0, 41)),
    13 => std_logic_vector(to_unsigned(0, 41)),
    14 => std_logic_vector(to_unsigned(0, 41)),
    15 => std_logic_vector(to_unsigned(1068497915, 41)),
    16 => std_logic_vector(to_unsigned(0, 41)),
    17 => std_logic_vector(to_unsigned(0, 41)),
    18 => std_logic_vector(to_unsigned(0, 41)),
    19 => std_logic_vector(to_unsigned(0, 41)),
    20 => std_logic_vector(to_unsigned(1070593021, 41)),
    21 => std_logic_vector(to_unsigned(0, 41)),
    22 => std_logic_vector(to_unsigned(0, 41)),
    23 => std_logic_vector(to_unsigned(0, 41)),
    24 => std_logic_vector(to_unsigned(0, 41)),
    25 => std_logic_vector(to_unsigned(1076884481, 41)),
    26 => std_logic_vector(to_unsigned(0, 41)),
    27 => std_logic_vector(to_unsigned(0, 41)),
    28 => std_logic_vector(to_unsigned(0, 41)),
    29 => std_logic_vector(to_unsigned(0, 41)),
    30 => std_logic_vector(to_unsigned(1072692221, 41)),
    31 => std_logic_vector(to_unsigned(0, 41)),
    32 => std_logic_vector(to_unsigned(0, 41)),
    33 => std_logic_vector(to_unsigned(0, 41)),
    34 => std_logic_vector(to_unsigned(0, 41)),
    35 => std_logic_vector(to_unsigned(1072692219, 41)),
    36 => std_logic_vector(to_unsigned(0, 41)),
    37 => std_logic_vector(to_unsigned(0, 41)),
    38 => std_logic_vector(to_unsigned(0, 41)),
    39 => std_logic_vector(to_unsigned(0, 41)),
    40 => std_logic_vector(to_unsigned(1070593021, 41)),
    41 => std_logic_vector(to_unsigned(0, 41)),
    42 => std_logic_vector(to_unsigned(0, 41)),
    43 => std_logic_vector(to_unsigned(0, 41)),
    44 => std_logic_vector(to_unsigned(0, 41)),
    45 => std_logic_vector(to_unsigned(1072690173, 41)),
    46 => std_logic_vector(to_unsigned(0, 41)),
    47 => std_logic_vector(to_unsigned(0, 41)),
    48 => std_logic_vector(to_unsigned(0, 41)),
    49 => std_logic_vector(to_unsigned(0, 41)),
    50 => std_logic_vector(to_unsigned(1070593021, 41)),
    51 => std_logic_vector(to_unsigned(0, 41)),
    52 => std_logic_vector(to_unsigned(0, 41)),
    53 => std_logic_vector(to_unsigned(0, 41)),
    54 => std_logic_vector(to_unsigned(0, 41)),
    55 => std_logic_vector(to_unsigned(1083173887, 41)),
    56 => std_logic_vector(to_unsigned(0, 41)),
    57 => std_logic_vector(to_unsigned(0, 41)),
    58 => std_logic_vector(to_unsigned(0, 41)),
    59 => std_logic_vector(to_unsigned(0, 41)),
    60 => std_logic_vector(to_unsigned(1570122973, 41)),
    61 => std_logic_vector(to_unsigned(0, 41)),
    62 => std_logic_vector(to_unsigned(0, 41)),
    63 => std_logic_vector(to_unsigned(0, 41)),
    64 => std_logic_vector(to_unsigned(0, 41)),
    65 => std_logic_vector(to_unsigned(1509369319, 41)),
    66 => std_logic_vector(to_unsigned(0, 41)),
    67 => std_logic_vector(to_unsigned(0, 41)),
    68 => std_logic_vector(to_unsigned(0, 41)),
    69 => std_logic_vector(to_unsigned(0, 41)),
    70 => std_logic_vector(to_unsigned(1477813615, 41)),
    71 => std_logic_vector(to_unsigned(0, 41)),
    72 => std_logic_vector(to_unsigned(0, 41)),
    73 => std_logic_vector(to_unsigned(0, 41)),
    74 => std_logic_vector(to_unsigned(0, 41)),
    75 => std_logic_vector(to_unsigned(1400210807, 41)),
    76 => std_logic_vector(to_unsigned(0, 41)),
    77 => std_logic_vector(to_unsigned(0, 41)),
    78 => std_logic_vector(to_unsigned(0, 41)),
    79 => std_logic_vector(to_unsigned(0, 41)),
    80 => std_logic_vector(to_unsigned(1276353805, 41)),
    81 => std_logic_vector(to_unsigned(0, 41)),
    82 => std_logic_vector(to_unsigned(0, 41)),
    83 => std_logic_vector(to_unsigned(0, 41)),
    84 => std_logic_vector(to_unsigned(0, 41)),
    85 => std_logic_vector(to_unsigned(1183972511, 41)),
    86 => std_logic_vector(to_unsigned(0, 41)),
    87 => std_logic_vector(to_unsigned(0, 41)),
    88 => std_logic_vector(to_unsigned(0, 41)),
    89 => std_logic_vector(to_unsigned(0, 41)),
    90 => std_logic_vector(to_unsigned(1131480145, 41)),
    91 => std_logic_vector(to_unsigned(0, 41)),
    92 => std_logic_vector(to_unsigned(0, 41)),
    93 => std_logic_vector(to_unsigned(0, 41)),
    94 => std_logic_vector(to_unsigned(0, 41)),
    95 => std_logic_vector(to_unsigned(1102089259, 41)),
    96 => std_logic_vector(to_unsigned(0, 41)),
    97 => std_logic_vector(to_unsigned(0, 41)),
    98 => std_logic_vector(to_unsigned(0, 41)),
    99 => std_logic_vector(to_unsigned(0, 41)),
    100 => std_logic_vector(to_unsigned(1087384597, 41)),
    101 => std_logic_vector(to_unsigned(0, 41)),
    102 => std_logic_vector(to_unsigned(0, 41)),
    103 => std_logic_vector(to_unsigned(0, 41)),
    104 => std_logic_vector(to_unsigned(0, 41)),
    105 => std_logic_vector(to_unsigned(1078989831, 41)),
    106 => std_logic_vector(to_unsigned(0, 41)),
    107 => std_logic_vector(to_unsigned(0, 41)),
    108 => std_logic_vector(to_unsigned(0, 41)),
    109 => std_logic_vector(to_unsigned(0, 41)),
    110 => std_logic_vector(to_unsigned(1074793475, 41)),
    111 => std_logic_vector(to_unsigned(0, 41)),
    112 => std_logic_vector(to_unsigned(0, 41)),
    113 => std_logic_vector(to_unsigned(0, 41)),
    114 => std_logic_vector(to_unsigned(0, 41)),
    115 => std_logic_vector(to_unsigned(1074791425, 41)),
    116 => std_logic_vector(to_unsigned(0, 41)),
    117 => std_logic_vector(to_unsigned(0, 41)),
    118 => std_logic_vector(to_unsigned(0, 41)),
    119 => std_logic_vector(to_unsigned(0, 41)),
    120 => std_logic_vector(to_unsigned(1074791425, 41)),
    121 => std_logic_vector(to_unsigned(0, 41)),
    122 => std_logic_vector(to_unsigned(0, 41)),
    123 => std_logic_vector(to_unsigned(0, 41)),
    124 => std_logic_vector(to_unsigned(0, 41)),
    125 => std_logic_vector(to_unsigned(1072694273, 41)),
    126 => std_logic_vector(to_unsigned(0, 41)),
    127 => std_logic_vector(to_unsigned(0, 41)),
    128 => std_logic_vector(to_unsigned(0, 41)),
    129 => std_logic_vector(to_unsigned(0, 41)),
    130 => std_logic_vector(to_unsigned(1072696319, 41)),
    131 => std_logic_vector(to_unsigned(0, 41)),
    132 => std_logic_vector(to_unsigned(0, 41)),
    133 => std_logic_vector(to_unsigned(0, 41)),
    134 => std_logic_vector(to_unsigned(0, 41)),
    135 => std_logic_vector(to_unsigned(1072688125, 41)),
    136 => std_logic_vector(to_unsigned(0, 41)),
    137 => std_logic_vector(to_unsigned(0, 41)),
    138 => std_logic_vector(to_unsigned(0, 41)),
    139 => std_logic_vector(to_unsigned(0, 41)),
    140 => std_logic_vector(to_unsigned(1072694269, 41)),
    141 => std_logic_vector(to_unsigned(0, 41)),
    142 => std_logic_vector(to_unsigned(0, 41)),
    143 => std_logic_vector(to_unsigned(0, 41)),
    144 => std_logic_vector(to_unsigned(0, 41)),
    145 => std_logic_vector(to_unsigned(1072690177, 41)),
    146 => std_logic_vector(to_unsigned(0, 41)),
    147 => std_logic_vector(to_unsigned(0, 41)),
    148 => std_logic_vector(to_unsigned(0, 41)),
    149 => std_logic_vector(to_unsigned(0, 41)),
    150 => std_logic_vector(to_unsigned(1070593023, 41)),
    151 => std_logic_vector(to_unsigned(0, 41)),
    152 => std_logic_vector(to_unsigned(0, 41)),
    153 => std_logic_vector(to_unsigned(0, 41)),
    154 => std_logic_vector(to_unsigned(0, 41)),
    155 => std_logic_vector(to_unsigned(1072690173, 41)),
    156 => std_logic_vector(to_unsigned(0, 41)),
    157 => std_logic_vector(to_unsigned(0, 41)),
    158 => std_logic_vector(to_unsigned(0, 41)),
    159 => std_logic_vector(to_unsigned(0, 41)),
    160 => std_logic_vector(to_unsigned(1070595071, 41)),
    161 => std_logic_vector(to_unsigned(0, 41)),
    162 => std_logic_vector(to_unsigned(0, 41)),
    163 => std_logic_vector(to_unsigned(0, 41)),
    164 => std_logic_vector(to_unsigned(0, 41)),
    165 => std_logic_vector(to_unsigned(1072690173, 41)),
    166 => std_logic_vector(to_unsigned(0, 41)),
    167 => std_logic_vector(to_unsigned(0, 41)),
    168 => std_logic_vector(to_unsigned(0, 41)),
    169 => std_logic_vector(to_unsigned(0, 41)),
    170 => std_logic_vector(to_unsigned(1070593019, 41)),
    171 => std_logic_vector(to_unsigned(0, 41)),
    172 => std_logic_vector(to_unsigned(0, 41)),
    173 => std_logic_vector(to_unsigned(0, 41)),
    174 => std_logic_vector(to_unsigned(0, 41)),
    175 => std_logic_vector(to_unsigned(1072690173, 41)),
    176 => std_logic_vector(to_unsigned(0, 41)),
    177 => std_logic_vector(to_unsigned(0, 41)),
    178 => std_logic_vector(to_unsigned(0, 41)),
    179 => std_logic_vector(to_unsigned(0, 41)),
    180 => std_logic_vector(to_unsigned(1070593019, 41)),
    181 => std_logic_vector(to_unsigned(0, 41)),
    182 => std_logic_vector(to_unsigned(0, 41)),
    183 => std_logic_vector(to_unsigned(0, 41)),
    184 => std_logic_vector(to_unsigned(0, 41))
  );

  signal test_mode_en : std_logic := '0';
  signal pb_addr       : integer range 0 to kPlaybackDepth-1 := 0;
  signal pb_word       : std_logic_vector(40 downto 0) := (others => '0');
  signal mux_dIn       : std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
  signal mux_validIn   : std_logic;

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

  -- final output (mirrored internally so the debug ILA below can read it back;
  -- an entity's own "out" port cannot be read inside its architecture) --
  signal final_validOut  : std_logic;
  signal final_dOut      : std_logic_vector(63 downto 0);

begin

  -- Text-pattern playback (drives mux_dIn/mux_validIn while test_mode_en='1').
  -- test_mode_en is only ever driven (by vio_1, below) inside the enDEBUG-gated
  -- channel; for every other channel it stays at its init value '0', so this
  -- process and the mux below are a no-op there and the real ADC stream passes
  -- straight through untouched.
  u_playback : process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' or test_mode_en = '0' then
        pb_addr <= 0;
        pb_word <= (others => '0');
      else
        pb_word <= kPlaybackRom(pb_addr);
        if pb_addr = kPlaybackDepth-1 then
          pb_addr <= 0;
        else
          pb_addr <= pb_addr + 1;
        end if;
      end if;
    end if;
  end process;

  mux_dIn     <= pb_word(40 downto 1) when test_mode_en = '1' else dIn;
  mux_validIn <= pb_word(0)           when test_mode_en = '1' else validIn;

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
      validIn     => mux_validIn,
      dIn         => mux_dIn,
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
      validDelimiter => validDelimiter,
      dInDelimiter   => dInDelimiter,

      -- dOut (64bit)
      validOut       => final_validOut,
      dOut           => final_dOut
    );

  validOut <= final_validOut;
  dOut     <= final_dOut;

  -- Debug ILA: only built into the one channel where enDEBUG is true
  -- (ODPBlockADC wires enDEBUG => GetDebugFlag(i) for exactly this purpose).
  gen_ila_debug : if enDEBUG generate
    u_ila_debug : ila_0
      PORT MAP (
        clk    => clk,
        probe0 => mux_dIn & mux_validIn,
        probe1 => supp_dOut & supp_typeOut & supp_validOut,
        probe2 => pileup_dOut & pileup_validOut,
        probe3(0) => sat_dOut,
        probe4(0) => validDelimiter,
        probe5 => final_dOut & final_validOut
      );

    u_vio_debug : vio_1
      PORT MAP (
        clk           => clk,
        probe_out0(0) => test_mode_en
      );
  end generate;

end Behavioral;
