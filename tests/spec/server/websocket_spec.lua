-- Tests for WebSocket implementation

describe("websocket", function()
	local websocket = require("claude-code-ide.server.websocket")

	describe("parse_http_headers", function()
		it("should parse valid WebSocket upgrade request", function()
			local request = table.concat({
				"GET / HTTP/1.1",
				"Host: localhost:54321",
				"Upgrade: websocket",
				"Connection: Upgrade",
				"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
				"Sec-WebSocket-Version: 13",
				"x-claude-code-ide-authorization: test-token",
				"",
				"",
			}, "\r\n")

			local headers = websocket._parse_http_headers(request)

			assert.are.equal("GET", headers.method)
			assert.are.equal("/", headers.path)
			assert.are.equal("localhost:54321", headers["host"])
			assert.are.equal("websocket", headers["upgrade"])
			assert.are.equal("Upgrade", headers["connection"])
			assert.are.equal("dGhlIHNhbXBsZSBub25jZQ==", headers["sec-websocket-key"])
			assert.are.equal("13", headers["sec-websocket-version"])
			assert.are.equal("test-token", headers["x-claude-code-ide-authorization"])
		end)

		it("should return nil for incomplete headers", function()
			local request = "GET / HTTP/1.1\r\nHost: localhost"
			local headers = websocket._parse_http_headers(request)
			assert.is_nil(headers)
		end)
	end)

	describe("validate_upgrade_request", function()
		it("should validate correct WebSocket request", function()
			local headers = {
				method = "GET",
				["upgrade"] = "websocket",
				["connection"] = "Upgrade",
				["sec-websocket-key"] = "test-key",
				["sec-websocket-version"] = "13",
			}

			assert.is_true(websocket._validate_upgrade_request(headers))
		end)

		it("should reject non-GET requests", function()
			local headers = {
				method = "POST",
				["upgrade"] = "websocket",
				["connection"] = "Upgrade",
				["sec-websocket-key"] = "test-key",
				["sec-websocket-version"] = "13",
			}

			assert.is_false(websocket._validate_upgrade_request(headers))
		end)

		it("should reject wrong version", function()
			local headers = {
				method = "GET",
				["upgrade"] = "websocket",
				["connection"] = "Upgrade",
				["sec-websocket-key"] = "test-key",
				["sec-websocket-version"] = "8",
			}

			assert.is_false(websocket._validate_upgrade_request(headers))
		end)
	end)
end)
