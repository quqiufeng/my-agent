import sys
sys.path.insert(0, SCRIPT_DIR)
import dingtalk_stream
from dingtalk_stream import Credential, ChatbotHandler, AckMessage

CLIENT_ID = "ding720rjzuvgldviwtp"
CLIENT_SECRET = "0FI812n9Xc0TIMX4ut72LM-DXlF8CL8dtaZml4a7qMLUyiqtxqf-h7o5LO0wkJ4H"
CHATBOT_TOPIC = "/v1.0/im/bot/messages/get"

class TestHandler(ChatbotHandler):
    async def process(self, callback: dingtalk_stream.CallbackMessage):
        print("=== 完整消息 ===")
        print(type(callback))
        print(dir(callback))
        print("=== data ===")
        print(callback.data)
        print("=== headers ===")
        print(dir(callback.headers))
        print("=== sender_id ===")
        print(callback.sender_id)
        return AckMessage.STATUS_OK, 'OK'

credential = Credential(CLIENT_ID, CLIENT_SECRET)
client = dingtalk_stream.DingTalkStreamClient(credential)
handler = TestHandler()
client.register_callback_handler(CHATBOT_TOPIC, handler)
print("启动...")
client.start_forever()
