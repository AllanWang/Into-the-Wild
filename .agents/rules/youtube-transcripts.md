# YouTube Transcript Extraction

When you need to read the content of a YouTube video (e.g., for research, extracting best practices, or referencing tutorial content):

1. Take the YouTube URL (e.g., `https://www.youtube.com/watch?v=XXXXXXXXXXX` or `https://youtu.be/XXXXXXXXXXX`)
2. Replace `youtube.com` with `youtubettt.com` (three t's) in the URL
3. Fetch that modified URL using `read_url_content` to get the plain-text transcript
4. The transcript includes timestamps and spoken text, which can then be analyzed or summarized

**Example**:
- Original: `https://www.youtube.com/watch?v=XXXXXXXXXXX`
- Transcript: `https://www.youtubettt.com/watch?v=XXXXXXXXXXX`

This is far more reliable than trying to scrape the YouTube page directly, which returns raw HTML/JavaScript instead of video content.
