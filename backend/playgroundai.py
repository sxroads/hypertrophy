from upsonic import Agent, Task

# Create an agent
agent = Agent(memory=True)

# Execute with Task object
task = Task("What is the capital of France?")
result = agent.do(task)
print(result)  # Output: 4

# Or execute directly with a string (auto-converted to Task)
result = agent.do(task)
print(result)  # Output: 4
