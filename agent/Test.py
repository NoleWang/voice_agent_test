#!/usr/bin/env python
# coding: utf-8

# In[19]:


import boto3
import asyncio
from dotenv import load_dotenv
from livekit.agents import JobContext, AgentSession, cli, WorkerOptions
from livekit.plugins.aws import stt as aws_stt, tts as aws_tts
from livekit.plugins import aws


# In[20]:


load_dotenv()


# ## Create sample audio data via Amazon Polly

# In[5]:


polly = boto3.client("polly", region_name="us-east-2")


# In[6]:


text = "您好，我要争议一笔在 BestBuy 发生的 150 美元交易。"
resp = polly.synthesize_speech(
    Text=text,
    TextType="text",
    OutputFormat="mp3",
    VoiceId="Zhiyu"
)


# In[7]:


with open("audio_file/dispute_test.mp3", "wb") as f:
    f.write(resp["AudioStream"].read())


# ## Define Your Custom Agent

# In[21]:


class Assistant(Agent):
    def __init__(self) -> None:
        llm = aws.LLM(model="anthropic.claude-sonnet-4-5-20250929-v1:0")
        stt = aws_stt.STT(language="en-US")
        tts = aws_tts.TTS()
        #tts = elevenlabs.TTS(voice_id="CwhRBWXzGAHq8TQ4Fs17")  # example with defined voice
        silero_vad = silero.VAD.load()

        super().__init__(
            instructions="""
                You are a helpful assistant communicating 
                via voice
            """,
            stt=stt,
            llm=llm,
            tts=tts,
            vad=silero_vad,
        )


# ## Create the Entrypoint

# In[22]:


async def entrypoint(ctx: JobContext):
    await ctx.connect()

    session = AgentSession()

    await session.start(
        room=ctx.room,
        agent=Assistant()
    )


# ## Setting up the app to run

# - To speak to the agent, unmute the microphone symbol on the left. You can ignore the 'Start Audio' button.
# - The agent will try to detect the language you are speaking. To help it, start by speaking a long phrase like "hello, how are you today" in the language of your choice.

# In[23]:


cli.run_app(
    WorkerOptions(entrypoint_fnc=entrypoint)
)


# In[ ]:




