module suifund::swap {
    use std::type_name;
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use suifund::suifund::{Self, ProjectRecord, ProjectAdminCap, SupporterReward, AdminCap};

    const COIN_TYPE: vector<u8> = b"coin_type";
    const TREASURY: vector<u8> = b"treasury";
    const STORAGE: vector<u8> = b"storage_sr";

    const EAlreadyInit: u64         = 100;
    const EExpectZeroDecimals: u64  = 101;
    const EInvalidTreasuryCap: u64  = 102;
    const ENotInit: u64             = 103;
    const ENotSameProject: u64      = 104;
    const EZeroCoin: u64            = 105;
    const ENotBegin: u64            = 106;

    public entry fun init_swap_by_project_admin<T>(
        project_admin_cap: &ProjectAdminCap,
        project_record: &mut ProjectRecord,
        treasury_cap: TreasuryCap<T>,
        metadata: &CoinMetadata<T>
    ) {
        suifund::check_project_cap(project_record, project_admin_cap);
        init_swap<T>(project_record, treasury_cap, metadata);
    }

    public entry fun init_swap_by_admin<T>(
        _: &AdminCap,
        project_record: &mut ProjectRecord,
        treasury_cap: TreasuryCap<T>,
        metadata: &CoinMetadata<T>
    ) {
        init_swap<T>(project_record, treasury_cap, metadata);
    }

    fun init_swap<T>(
        project_record: &mut ProjectRecord,
        treasury_cap: TreasuryCap<T>,
        metadata: &CoinMetadata<T>
    ) {
        assert!(!suifund::exists_in_project<std::ascii::String>(project_record, std::ascii::string(COIN_TYPE)), EAlreadyInit);
        assert!(suifund::project_begin_status(project_record), ENotBegin);
        assert!(coin::total_supply<T>(&treasury_cap) == 0, EInvalidTreasuryCap);
        assert!(coin::get_decimals<T>(metadata) == 0, EExpectZeroDecimals);

        let coin_type = type_name::into_string(type_name::get_with_original_ids<T>());
        suifund::add_df_in_project<std::ascii::String, std::ascii::String>(project_record, std::ascii::string(COIN_TYPE), coin_type);
        suifund::add_df_in_project<std::ascii::String, TreasuryCap<T>>(project_record, std::ascii::string(TREASURY), treasury_cap);
        suifund::add_df_in_project<std::ascii::String, vector<SupporterReward>>(project_record, std::ascii::string(STORAGE), vector::empty<SupporterReward>());
    }

    public fun sr_to_coin<T>(
        project_record: &mut ProjectRecord,
        supporter_reward: SupporterReward,
        ctx: &mut TxContext
    ): Coin<T> {
        assert!(suifund::exists_in_project<std::ascii::String>(project_record, std::ascii::string(COIN_TYPE)), ENotInit);
        assert!(suifund::project_name(project_record) == suifund::sr_name(&supporter_reward), ENotSameProject);
        let value = suifund::sr_amount(&supporter_reward);
        let storage_sr = suifund::borrow_mut_in_project<std::ascii::String, vector<SupporterReward>>(project_record, std::ascii::string(STORAGE));

        if (vector::is_empty<SupporterReward>(storage_sr)) {
            vector::push_back<SupporterReward>(storage_sr, supporter_reward);
        } else {
            let sr_mut = vector::borrow_mut<SupporterReward>(storage_sr, 0);
            suifund::do_merge(sr_mut, supporter_reward);
        };

        let treasury = suifund::borrow_mut_in_project<std::ascii::String, TreasuryCap<T>>(project_record, std::ascii::string(TREASURY));
        coin::mint<T>(treasury, value, ctx)
    }

    public entry fun sr_to_coin_swap<T>(
        project_record: &mut ProjectRecord,
        supporter_reward: SupporterReward,
        ctx: &mut TxContext
    ) {
        let coin = sr_to_coin<T>(project_record, supporter_reward, ctx);
        transfer::public_transfer(coin, ctx.sender());
    }

    public fun coin_to_sr<T>(
        project_record: &mut ProjectRecord,
        sr_coin: Coin<T>,
        ctx: &mut TxContext
    ): SupporterReward {
        assert!(suifund::exists_in_project<std::ascii::String>(project_record, std::ascii::string(COIN_TYPE)), ENotInit);
        let treasury = suifund::borrow_mut_in_project<std::ascii::String, TreasuryCap<T>>(project_record, std::ascii::string(TREASURY));
        let value = coin::burn<T>(treasury, sr_coin);
        assert!(value > 0, EZeroCoin);

        let storage_sr = suifund::borrow_mut_in_project<std::ascii::String, vector<SupporterReward>>(project_record, std::ascii::string(STORAGE));
        let sr_b = vector::borrow<SupporterReward>(storage_sr, 0);
        let sr_tsv = suifund::sr_amount(sr_b);

        if (sr_tsv == value) {
            vector::pop_back<SupporterReward>(storage_sr)
        } else {
            let sr_bm = vector::borrow_mut<SupporterReward>(storage_sr, 0);
            suifund::do_split(sr_bm, value, ctx)
        }
    }

    public entry fun coin_to_sr_swap<T>(
        project_record: &mut ProjectRecord,
        sr_coin: Coin<T>,
        ctx: &mut TxContext
    ) {
        let sr = coin_to_sr<T>(project_record, sr_coin, ctx);
        transfer::public_transfer(sr, ctx.sender());
    }

    // for update CoinMetadata purposes
    public fun borrow_treasury_cap_by_project_admin<T>(
        project_record: &mut ProjectRecord,
        project_admin_cap: &ProjectAdminCap
    ): &TreasuryCap<T> {
        suifund::check_project_cap(project_record, project_admin_cap);
        assert!(suifund::exists_in_project<std::ascii::String>(project_record, std::ascii::string(COIN_TYPE)), ENotInit);
        suifund::borrow_in_project<std::ascii::String, TreasuryCap<T>>(project_record, std::ascii::string(TREASURY))
    }

    public fun borrow_treasury_cap_by_admin<T>(
        _: &AdminCap,
        project_record: &mut ProjectRecord
    ): &TreasuryCap<T> {
        assert!(suifund::exists_in_project<std::ascii::String>(project_record, std::ascii::string(COIN_TYPE)), ENotInit);
        suifund::borrow_in_project<std::ascii::String, TreasuryCap<T>>(project_record, std::ascii::string(TREASURY))
    }

    // ======== Read Functions =========

    public fun get_coin_type(project_record: &ProjectRecord): &std::ascii::String {
        suifund::borrow_in_project<std::ascii::String, std::ascii::String>(project_record, std::ascii::string(COIN_TYPE))
    }

    public fun get_total_supply<T>(project_record: &ProjectRecord): u64 {
        let treasury = suifund::borrow_in_project<std::ascii::String, TreasuryCap<T>>(project_record, std::ascii::string(TREASURY));
        coin::total_supply<T>(treasury)
    }
}