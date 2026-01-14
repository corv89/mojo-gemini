"""Simple Gemini client example.

Fetches a page from a Gemini server and prints the response.

Build and run:
    ./build.sh examples/simple_client.mojo simple_client
    DYLD_LIBRARY_PATH=/Users/corv/Src/.venv/lib/python3.12/site-packages/modular/lib ./simple_client
"""

from mojo_gemini import GeminiClient, status_description


fn main() raises:
    # Default URL to fetch
    var url = "gemini://geminiprotocol.net/"

    print("Fetching:", url)
    print()

    var client = GeminiClient()
    var response = client.request(url)

    print("Status:", response.status.code, "-", status_description(response.status))
    print("Meta:", response.meta)
    print()

    if response.is_success():
        print("Content type:", response.mime_type())
        print()
        print("--- Body ---")
        var body = response.body()
        # Print first 2000 chars
        if len(body) > 2000:
            print(body[:2000])
            print("... (truncated, total", len(body), "bytes)")
        else:
            print(body)
    elif response.is_redirect():
        print("Redirect to:", response.meta)
    elif response.is_input():
        print("Server requests input:", response.meta)
    else:
        print("Error:", response.meta)
