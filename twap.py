import numpy as np
import matplotlib.pyplot as plt

# Function to calculate arithmetic TWAP
def arithmetic_twap(prices):
    return np.mean(prices)

# Function to calculate geometric TWAP
def geometric_twap(prices):
    # Mathematical Proof:
    # Let's start with the definition of the geometric mean for a set of numbers [x₁, x₂, ..., xₙ]:
    # Geometric Mean = (x₁ × x₂ × ... × xₙ)^(1/n)
    # Now, let's see how the logarithmic approach works:
    # Take the natural logarithm of the geometric mean:
    # ln(Geometric Mean) = ln((x₁ × x₂ × ... × xₙ)^(1/n))
    # Using the property of logarithms where ln(a^b) = b·ln(a):
    # ln(Geometric Mean) = (1/n) · ln(x₁ × x₂ × ... × xₙ)
    # Using the property of logarithms where ln(a×b) = ln(a) + ln(b):
    # ln(Geometric Mean) = (1/n) · [ln(x₁) + ln(x₂) + ... + ln(xₙ)]
    # This is equivalent to:
    # ln(Geometric Mean) = mean(ln(x₁), ln(x₂), ..., ln(xₙ))
    # Taking the exponential of both sides:
    # Geometric Mean = exp(mean(ln(x₁), ln(x₂), ..., ln(xₙ)))
    # This is exactly what the code np.exp(np.mean(np.log(prices))) does!
    return np.exp(np.mean(np.log(prices)))

# Price data simulation
np.random.seed(2)  # For reproducibility
time_steps = 300  # Window of 200 blocks (approximately 30 minutes with 6s blocks)
base_price = 20  # Initial price

# Plateau parameters
plateau_start = 60  # Start of plateau after 60 time steps
plateau_length = 50  # Length of plateau
manipulation_start = plateau_start + 40  # Start of manipulation phase
manipulation_length = 30  # Length of manipulation phase

# Scenario 1: Linear price increase followed by a plateau with manipulation
prices_increase = np.zeros(time_steps)
# Increase phase
prices_increase[:plateau_start] = np.linspace(base_price, base_price * 2, plateau_start)
# Plateau phase
prices_increase[plateau_start:] = base_price * 2
# Manipulation phase (price spike during plateau)
prices_increase[manipulation_start:manipulation_start+manipulation_length] = base_price * 4

# Scenario 2: Linear price decrease followed by a plateau with manipulation
prices_decrease = np.zeros(time_steps)
# Decrease phase
prices_decrease[:plateau_start] = np.linspace(base_price, base_price * 0.5, plateau_start)
# Plateau phase
prices_decrease[plateau_start:] = base_price * 0.5
# Manipulation phase (price drop during plateau)
prices_decrease[manipulation_start:manipulation_start+manipulation_length] = base_price * 0.3

# Add random noise to both scenarios
noise = np.random.normal(0, 1, time_steps)
prices_increase = prices_increase + noise
prices_decrease = prices_decrease + noise

# Calculate TWAP on a sliding window
window_size = 50  # Window size for TWAP
arith_twap_increase = [arithmetic_twap(prices_increase[i:i+window_size]) 
                       for i in range(len(prices_increase) - window_size + 1)]
geom_twap_increase = [geometric_twap(prices_increase[i:i+window_size]) 
                      for i in range(len(prices_increase) - window_size + 1)]

arith_twap_decrease = [arithmetic_twap(prices_decrease[i:i+window_size]) 
                       for i in range(len(prices_decrease) - window_size + 1)]
geom_twap_decrease = [geometric_twap(prices_decrease[i:i+window_size]) 
                      for i in range(len(prices_decrease) - window_size + 1)]

# Time for graphs (adjusted to window)
time = np.arange(window_size - 1, len(prices_increase))

# Graph 1: Price increase
plt.figure(figsize=(12, 6))
plt.plot(np.arange(len(prices_increase)), prices_increase, label='Price', color='gray', alpha=0.5)
plt.plot(time, arith_twap_increase, label='Arithmetic TWAP', color='blue')
plt.plot(time, geom_twap_increase, label='Geometric TWAP', color='red')
plt.title("TWAP Comparison")
plt.xlabel("Time (blocks)")
plt.ylabel("Price")
plt.legend()
plt.grid(True)
plt.show()