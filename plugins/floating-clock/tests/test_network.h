// Network service catalog test fixtures.
//
// Locks the parsing layer that drives the network picker bar. The bar
// switches the system's default route, so a parse bug here is not cosmetic —
// emitting a wrong or short service list makes `networksetup
// -ordernetworkservices` reject the whole command, and emitting a service
// with no BSD device would kill connectivity.
//
// Shared `failures` linkage matches test_levers.h — defined in test_session.m.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_network_parse_basic(void);
void test_network_parse_tolerates_header_and_blanks(void);
void test_network_parse_disabled_marker(void);
void test_network_parse_service_without_device(void);
void test_network_parse_garbage_is_empty(void);
void test_network_device_to_name_lookup(void);
void test_network_reorder_puts_choice_first(void);
void test_network_reorder_preserves_all_services(void);
void test_network_reorder_rejects_unknown_service(void);
void test_network_switchable_filters_deviceless_and_disabled(void);
void test_network_switchable_excludes_dead_modem_services(void);
void test_network_switchable_keeps_link_local_device(void);
void test_network_switchable_nil_vs_empty_liveness(void);

NS_ASSUME_NONNULL_END
