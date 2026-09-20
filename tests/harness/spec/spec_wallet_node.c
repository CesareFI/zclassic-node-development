/* Copyright 2026 Rhett Creighton - Apache License 2.0
 *
 * KATHY SIERRA PRINCIPLE: Running a full node is a superpower.
 * The command center should make the user feel like a pilot,
 * not a sysadmin reading log files.
 *
 * "I can see the entire network. I validate my own transactions.
 *  I don't trust anyone. I AM the network." */

#include "test/spec_helpers.h"
#include "sync/sync_state.h"

static bool enter_idle_for_ibd_render(void)
{
    enum sync_state state = sync_get_state();
    if (state == SYNC_REORG) {
        if (!sync_set_state(SYNC_REORG_RECOVERY,
                            "wallet node IBD render test"))
            return false;
        state = SYNC_REORG_RECOVERY;
    }
    if (state != SYNC_IDLE &&
        !sync_set_state(SYNC_IDLE, "wallet node IBD render test"))
        return false;
    return true;
}

int spec_wallet_node(void)
{
    wallet_view_init(NULL);

    FEATURE("User feels like a network sovereign") {
        STORY("command center shows the user IS the network") {
            GIVEN("user opens node page")
                GET("/wallet/node");
            THEN("page title conveys power")
                EXPECT(has("Command Center"));
            THEN("block height shows chain awareness")
                EXPECT(has("Block Height"));
            THEN("peer count shows network participation")
                EXPECT(has("Connected Peers"));
            PASS();
        }

        STORY("user sees their unique identity on the network") {
            GIVEN("node page loads")
                GET("/wallet/node");
            THEN("version string shows what they're running")
                EXPECT(has("ZClassic23:0.1.0"));
            THEN("protocol capabilities are listed")
                EXPECT(has("NODE_NETWORK"));
            PASS();
        }
    }

    FEATURE("Tor makes the user feel untraceable") {
        STORY("Tor status is visible without digging") {
            GIVEN("node page loads")
                GET("/wallet/node");
            THEN("Tor section exists prominently")
                EXPECT(has("Tor Hidden Service"));
            PASS();
        }
    }

    FEATURE("User can see every peer they're connected to") {
        STORY("peer table shows real connections") {
            GIVEN("node page loads")
                GET("/wallet/node");
            THEN("table headers exist")
                EXPECT(has("Address"));
            THEN("empty state is friendly, not scary")
                EXPECT(has("Connecting to network"));
            PASS();
        }
    }

    FEATURE("IBD keeps the command center responsive") {
        STORY("whole-UTXO presentation aggregates wait until sync is quiet") {
            GIVEN("the node is downloading headers")
                bool state_ok = enter_idle_for_ibd_render();
                state_ok = state_ok && sync_set_state(
                    SYNC_HEADERS_DOWNLOAD, "wallet node IBD render test");
            WHEN("the command center renders")
                GET("/wallet/node");
            THEN("expensive changing totals are explicitly deferred")
                EXPECT(state_ok);
                EXPECT(has("UTXO Set"));
                EXPECT(has("Deferred"));
            THEN("the shared sync state is restored")
                EXPECT(sync_set_state(SYNC_IDLE,
                                      "wallet node IBD render test cleanup"));
            PASS();
        }
    }

    FEATURE("Power tools are accessible, not buried") {
        STORY("coin audit and explorer are one tap away") {
            GIVEN("node page loads")
                GET("/wallet/node");
            THEN("coin audit is linked")
                EXPECT(has("Coin Audit"));
            THEN("block explorer is linked")
                EXPECT(has("Block Explorer"));
            PASS();
        }

        STORY("coins page has breadcrumb back") {
            GIVEN("coins page loads")
                GET("/wallet/coins");
            THEN("breadcrumb or loading state")
                EXPECT(has("Coin Audit") || is_loading());
            PASS();
        }
    }

    FEATURE("No dead ends in the interface") {
        STORY("node tab is always reachable") {
            GIVEN("any page loads")
                GET("/wallet");
            THEN("node tab exists in nav")
                EXPECT(has(">Node<"));
                EXPECT(has("/wallet/node"));
            PASS();
        }
    }

    SPEC_SUMMARY();
    return SPEC_FAILURES();
}
