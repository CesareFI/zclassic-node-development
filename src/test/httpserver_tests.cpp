// Copyright (c) 2026 The Zclassic developers
// Distributed under the MIT software license, see COPYING.

#include "compat.h"
#include "httpserver.h"

#include <boost/test/unit_test.hpp>
#include <event2/bufferevent.h>
#include <event2/event.h>
#include <event2/http.h>
#include <chrono>
#include <memory>
#include <thread>

namespace {
struct HTTPFixture {
    event_base* base = nullptr;
    evhttp* server = nullptr;
    evhttp_connection* client = nullptr;
    bufferevent* retained = nullptr;
    evutil_socket_t descriptor = -1;
    bool serverClosed = false;
    bool clientDone = false;
    bool sameBuffer = true;
    int response = 0;

    ~HTTPFixture()
    {
        if (client) evhttp_connection_free(client);
        if (server) evhttp_free(server);
        if (retained) bufferevent_free(retained);
        if (base) {
            event_base_loop(base, EVLOOP_NONBLOCK);
            event_base_free(base);
        }
    }

    void Start(bool close = true)
    {
        base = event_base_new();
        BOOST_REQUIRE(base);
        server = CreateHTTPServer(base);
        BOOST_REQUIRE(server);
        evhttp_set_gencb(server, [](evhttp_request* request, void* context) {
            auto& self = *static_cast<HTTPFixture*>(context);
            auto* connection = evhttp_request_get_connection(request);
            auto* buffer = evhttp_connection_get_bufferevent(connection);
            if (self.retained) {
                self.sameBuffer = self.sameBuffer && self.retained == buffer;
            } else {
                self.retained = buffer;
                // Simulate a reference held by a callback that has not returned.
                bufferevent_incref(self.retained);
                self.descriptor = bufferevent_getfd(self.retained);
            }
            evhttp_connection_set_closecb(connection, [](evhttp_connection*, void* context) {
                static_cast<HTTPFixture*>(context)->serverClosed = true;
            }, context);
            evhttp_send_reply(request, 200, "OK", nullptr);
        }, this);
        auto* bound = evhttp_bind_socket_with_handle(server, "127.0.0.1", 0);
        BOOST_REQUIRE(bound);
        sockaddr_in address{};
        ev_socklen_t length = sizeof(address);
        BOOST_REQUIRE_EQUAL(getsockname(evhttp_bound_socket_get_fd(bound),
            reinterpret_cast<sockaddr*>(&address), &length), 0);
        client = evhttp_connection_base_new(base, nullptr, "127.0.0.1", ntohs(address.sin_port));
        BOOST_REQUIRE(client);
        SendRequest(close);
    }

    void SendRequest(bool close)
    {
        clientDone = false;
        std::unique_ptr<evhttp_request, decltype(&evhttp_request_free)> request(
            evhttp_request_new([](evhttp_request* request, void* context) {
            auto& self = *static_cast<HTTPFixture*>(context);
            self.clientDone = true;
            self.response = request ? evhttp_request_get_response_code(request) : 0;
        }, this), &evhttp_request_free);
        BOOST_REQUIRE(request);
        BOOST_REQUIRE_EQUAL(evhttp_add_header(evhttp_request_get_output_headers(request.get()),
                                             "Connection", close ? "close" : "keep-alive"), 0);
        // evhttp_make_request takes ownership, including on failure.
        BOOST_REQUIRE_EQUAL(evhttp_make_request(client, request.release(), EVHTTP_REQ_GET, "/"), 0);
    }

    void WaitFor(const bool& condition)
    {
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        while (!condition && std::chrono::steady_clock::now() < deadline) {
            BOOST_REQUIRE_GE(event_base_loop(base, EVLOOP_NONBLOCK), 0);
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        BOOST_REQUIRE(condition);
    }

    bool SocketOpen() const
    {
        int type = 0;
        ev_socklen_t length = sizeof(type);
        return getsockopt(descriptor, SOL_SOCKET, SO_TYPE,
                          reinterpret_cast<char*>(&type), &length) == 0;
    }
};
}

BOOST_FIXTURE_TEST_SUITE(httpserver_tests, HTTPFixture)

BOOST_AUTO_TEST_CASE(socket_lives_until_final_buffered_event_reference)
{
    Start();
    WaitFor(serverClosed);
    BOOST_REQUIRE(retained);
    BOOST_CHECK_MESSAGE(SocketOpen(), "HTTP closed the socket while a callback still owns its buffer");
    bufferevent_free(retained);
    retained = nullptr;
    // Run deferred destruction before checking the descriptor was released.
    BOOST_REQUIRE_GE(event_base_loop(base, EVLOOP_NONBLOCK), 0);
    BOOST_CHECK(!SocketOpen());
    WaitFor(clientDone);
    BOOST_CHECK_EQUAL(response, 200);
}

BOOST_AUTO_TEST_CASE(keepalive_reuses_connection_before_explicit_close)
{
    Start(false);
    WaitFor(clientDone);
    BOOST_CHECK_EQUAL(response, 200);
    BOOST_CHECK(!serverClosed);
    BOOST_CHECK(SocketOpen());
    SendRequest(true);
    WaitFor(clientDone);
    WaitFor(serverClosed);
    BOOST_CHECK_EQUAL(response, 200);
    BOOST_CHECK(sameBuffer);
}

BOOST_AUTO_TEST_SUITE_END()
