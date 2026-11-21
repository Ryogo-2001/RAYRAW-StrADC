-- File: DataSelector.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;
use mylib.defDelimiter.all;

entity DataSelector is
  generic (
    kNumSample     : integer := 4;
    kWidthAdcData  : integer := 10;
    kWidthIntegral : integer := 32;
    kMaxBufWords   : integer := 256;
    kPreSamples    : integer range 1 to 15 := 2;
    kClkPerWord    : integer range 1 to 64 := 5;
    kEvQueueDepth  : integer range 2 to 16 := 4
  );
  port (
    clk            : in  std_logic;
    srst           : in  std_logic;

    -- data in (ADC)
    raw_validIn    : in  std_logic;
    raw_dIn        : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    raw_typeIn     : in  std_logic_vector(kWidthAdcSFType-1 downto 0);

    -- data in 
    intg_val       : in  std_logic_vector(kWidthIntegral-1 downto 0);
    peak_val       : in  std_logic_vector(kWidthAdcData-1 downto 0);
    tot_val        : in  std_logic_vector(kWidthIntegral-1 downto 0);
    isSat          : in  std_logic;
    isPileup       : in  std_logic;
    pileup_valid   : in  std_logic;

    -- HBD in (64bit)
    validDelimiter : in  std_logic;
    dInDelimiter   : in  std_logic_vector(63 downto 0);

    -- Data flow control
    daqOn           : in  std_logic := '1';
    hbfThrottlingOn : in  std_logic := '0';
    triggerGate     : in  std_logic := '1';
    signBit         : in  std_logic := '0';

    -- Data out
    validOut       : out std_logic;
    dOut           : out std_logic_vector(63 downto 0)
  );
end DataSelector;

architecture Behavioral of DataSelector is

  constant kWidthBus : integer := kNumSample * kWidthAdcData;

  -- memory
  type t_data_buf is array (0 to kMaxBufWords-1) of std_logic_vector(kWidthBus-1 downto 0);
  type t_type_buf is array (0 to kMaxBufWords-1) of std_logic_vector(kWidthAdcSFType-1 downto 0);

  signal buf_d : t_data_buf;
  signal buf_t : t_type_buf;

  attribute ram_style : string;
  attribute ram_style of buf_d : signal is "block";
  attribute ram_style of buf_t : signal is "block";

  signal buf_d_q     : std_logic_vector(kWidthBus-1 downto 0);
  signal buf_t_q     : std_logic_vector(kWidthAdcSFType-1 downto 0);
  signal out_active  : std_logic := '0';

  signal wr_ptr     : integer range 0 to kMaxBufWords-1 := 0;
  signal rd_ptr     : integer range 0 to kMaxBufWords-1 := 0;
  signal lock_ptr   : integer range 0 to kMaxBufWords-1;
  signal wr_we      : std_logic;
  signal wr_drop    : std_logic := '0';
  signal is_head    : std_logic;
  signal space_full : std_logic;
  signal q_full     : std_logic;

  type t_start_q is array (0 to kEvQueueDepth-1) of integer range 0 to kMaxBufWords-1;
  type t_intg_q  is array (0 to kEvQueueDepth-1) of std_logic_vector(kWidthIntegral-1 downto 0);
  type t_peak_q  is array (0 to kEvQueueDepth-1) of std_logic_vector(kWidthAdcData-1 downto 0);

  signal q_start    : t_start_q := (others => 0);
  signal q_intg     : t_intg_q;
  signal q_tot      : t_intg_q;
  signal q_peak     : t_peak_q;
  signal q_keep     : std_logic_vector(kEvQueueDepth-1 downto 0) := (others => '0');
  signal q_raw      : std_logic_vector(kEvQueueDepth-1 downto 0) := (others => '0');
  signal q_ovf      : std_logic_vector(kEvQueueDepth-1 downto 0) := (others => '0');
  signal q_rdy      : std_logic_vector(kEvQueueDepth-1 downto 0) := (others => '0');
  signal q_head     : integer range 0 to kEvQueueDepth-1 := 0;
  signal q_tail     : integer range 0 to kEvQueueDepth-1 := 0;
  signal q_cnt      : integer range 0 to kEvQueueDepth := 0;
  signal cur_slot   : integer range 0 to kEvQueueDepth-1 := 0;
  signal cur_pushed : std_logic := '0';
  signal fill_slot  : integer range 0 to kEvQueueDepth-1 := 0;
  signal fill_en    : std_logic := '0';

  type t_state is (sIdle, sRaw, sSum, sHbd);
  signal state        : t_state := sIdle;
  signal req_hbd      : std_logic := '0';
  signal reg_hbd_data : std_logic_vector(63 downto 0);
  signal reg_hbd_daq  : std_logic := '0';
  signal hbd_wait     : integer range 0 to kEvQueueDepth := 0;

  -- word counter
  signal gen_words    : unsigned(kPosHbdGenSize'length-4 downto 0) := (others => '0');

  -- HBD delay
  constant kHbdDelay : integer := kPreSamples * kClkPerWord + 2;
  signal valid_shift : std_logic_vector(kHbdDelay-1 downto 0) := (others => '0');
  type t_data_shift is array (0 to kHbdDelay-1) of std_logic_vector(63 downto 0);
  signal data_shift  : t_data_shift := (others => (others => '0'));

  signal daq_shift   : std_logic_vector(kHbdDelay downto 0) := (others => '0');
  signal thr_shift   : std_logic_vector(kHbdDelay downto 0) := (others => '0');
  signal daq_al      : std_logic;
  signal thr_al      : std_logic;

  function next_addr(a : integer) return integer is
  begin
    if a = kMaxBufWords-1 then
      return 0;
    else
      return a + 1;
    end if;
  end function;

  function next_slot(a : integer) return integer is
  begin
    if a = kEvQueueDepth-1 then
      return 0;
    else
      return a + 1;
    end if;
  end function;

begin

  -- HBD delay process
  u_hbd_delay : process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        valid_shift <= (others => '0');
        data_shift  <= (others => (others => '0'));
        daq_shift   <= (others => '0');
        thr_shift   <= (others => '0');
      else
        valid_shift(0) <= validDelimiter;
        data_shift(0)  <= dInDelimiter;
        daq_shift(0)   <= daqOn;
        thr_shift(0)   <= hbfThrottlingOn;
        -- shift process
        for i in 1 to kHbdDelay-1 loop
          valid_shift(i) <= valid_shift(i-1);
          data_shift(i)  <= data_shift(i-1);
        end loop;
        for i in 1 to kHbdDelay loop
          daq_shift(i) <= daq_shift(i-1);
          thr_shift(i) <= thr_shift(i-1);
        end loop;
      end if;
    end if;
  end process;

  daq_al <= daq_shift(kHbdDelay-1) when signBit = '0' else daq_shift(kHbdDelay);
  thr_al <= thr_shift(kHbdDelay-1) when signBit = '0' else thr_shift(kHbdDelay);

  -- Buffer
  is_head    <= '1' when raw_typeIn = kCTypeSfHead else '0';
  q_full     <= '1' when q_cnt = kEvQueueDepth else '0';
  lock_ptr   <= rd_ptr when state = sRaw else q_start(q_head);
  space_full <= '1' when q_cnt > 0 and next_addr(wr_ptr) = lock_ptr else '0';
  wr_we      <= raw_validIn when (is_head = '1' and q_full = '0' and space_full = '0') or
                                 (is_head = '0' and wr_drop = '0' and space_full = '0') else '0';

  u_write : process(clk)
  begin
    if rising_edge(clk) then
      if wr_we = '1' then
        buf_d(wr_ptr) <= raw_dIn;
        buf_t(wr_ptr) <= raw_typeIn;
      end if;
    end if;
  end process;

  u_buf_read : process(clk)
  begin
    if rising_edge(clk) then
      buf_d_q <= buf_d(rd_ptr);
      buf_t_q <= buf_t(rd_ptr);
    end if;
  end process;

  u_ctrl : process(clk)
    variable v_push : integer range 0 to 1;
    variable v_pop  : integer range 0 to 1;
  begin
    if rising_edge(clk) then
      if srst = '1' then
        wr_ptr       <= 0;
        rd_ptr       <= 0;
        wr_drop      <= '0';
        q_keep       <= (others => '0');
        q_raw        <= (others => '0');
        q_ovf        <= (others => '0');
        q_rdy        <= (others => '0');
        q_head       <= 0;
        q_tail       <= 0;
        q_cnt        <= 0;
        cur_slot     <= 0;
        cur_pushed   <= '0';
        fill_slot    <= 0;
        fill_en      <= '0';
        state        <= sIdle;
        out_active   <= '0';
        req_hbd      <= '0';
        reg_hbd_daq  <= '0';
        hbd_wait     <= 0;
        gen_words    <= (others => '0');
        validOut     <= '0';
      else
        v_push := 0;
        v_pop  := 0;

        if pileup_valid = '1' then
          if fill_en = '1' then
            q_rdy(fill_slot)  <= '1';
            q_raw(fill_slot)  <= isSat or isPileup;
            q_intg(fill_slot) <= intg_val;
            q_peak(fill_slot) <= peak_val;
            q_tot(fill_slot)  <= tot_val;
          end if;
          fill_en <= '0';
        end if;

        if raw_validIn = '1' then
          if is_head = '1' then
            if q_full = '0' and space_full = '0' then
              v_push := 1;
              q_start(q_tail) <= wr_ptr;
              q_keep(q_tail)  <= daq_al and (not thr_al) and triggerGate;
              q_ovf(q_tail)   <= '0';
              q_rdy(q_tail)   <= '0';
              cur_slot        <= q_tail;
              cur_pushed      <= '1';
              wr_drop         <= '0';
            else
              cur_pushed      <= '0';
              wr_drop         <= '1';
            end if;
          elsif wr_drop = '0' and space_full = '1' then
            wr_drop           <= '1';
            q_ovf(cur_slot)   <= '1';
          end if;

          if wr_we = '1' then
            wr_ptr <= next_addr(wr_ptr);
          end if;

          if raw_typeIn = kCTypeSfTrail then
            fill_en   <= cur_pushed;
            fill_slot <= cur_slot;
          end if;
        end if;

        validOut <= '0';

        case state is
          when sIdle =>
            if req_hbd = '1' and hbd_wait = 0 then
              validOut <= reg_hbd_daq;
              dOut     <= reg_hbd_data;
              state    <= sHbd;

            elsif q_cnt > 0 and q_rdy(q_head) = '1' then
              if q_keep(q_head) = '0' or (q_raw(q_head) = '1' and q_ovf(q_head) = '1') then
                v_pop := 1;
              elsif q_raw(q_head) = '1' then
                rd_ptr     <= q_start(q_head);
                out_active <= '0';
                state      <= sRaw;
              else
                validOut           <= '1';
                dOut(63 downto 60) <= "00" & kCTypeSfPayload;
                dOut(59 downto 40) <= (others => '0');
                dOut(39 downto 0)  <= q_intg(q_head) & x"00";
                gen_words          <= gen_words + 1;
                state              <= sSum;
              end if;
            end if;

          when sRaw =>
            if out_active = '1' and buf_t_q = kCTypeSfTrail then
              out_active <= '0';
              v_pop      := 1;
              state      <= sIdle;
            else
              rd_ptr     <= next_addr(rd_ptr);
              out_active <= '1';
            end if;

            if out_active = '1' then
              validOut           <= '1';
              dOut(63 downto 60) <= "00" & buf_t_q;
              dOut(59 downto 40) <= (others => '0');
              dOut(39 downto 0)  <= buf_d_q;
              gen_words          <= gen_words + 1;
            end if;

          when sSum =>
            validOut           <= '1';
            dOut(63 downto 60) <= "00" & kCTypeSfTrail;
            dOut(59 downto 40) <= (others => '0');
            dOut(39 downto 0)  <= q_tot(q_head)(29 downto 0) & q_peak(q_head);
            gen_words          <= gen_words + 1;
            v_pop              := 1;
            state              <= sIdle;

          when sHbd =>
            validOut                     <= reg_hbd_daq;
            dOut                         <= (others => '0');
            dOut(kPosHbdDataType'range)  <= kDatatypeHeartbeatT2;
            dOut(kPosHbdGenSize'range)   <= std_logic_vector(gen_words) & "000";
            gen_words                    <= (others => '0');
            req_hbd                      <= '0';
            state                        <= sIdle;
        end case;

        if v_pop = 1 then
          q_rdy(q_head) <= '0';
          q_head        <= next_slot(q_head);
        end if;
        if v_push = 1 then
          q_tail <= next_slot(q_tail);
        end if;
        q_cnt <= q_cnt + v_push - v_pop;

        if valid_shift(kHbdDelay-1) = '1' and req_hbd = '0' then
          req_hbd      <= '1';
          reg_hbd_data <= data_shift(kHbdDelay-1);
          reg_hbd_daq  <= daq_al;
          hbd_wait     <= q_cnt + v_push - v_pop;
        elsif req_hbd = '1' and v_pop = 1 and hbd_wait > 0 then
          hbd_wait     <= hbd_wait - 1;
        end if;

      end if;
    end if;
  end process;

end Behavioral;
