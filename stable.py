import numpy as np
import matplotlib.pyplot as plt
from typing import Tuple, List
from decimal import Decimal, getcontext
from scipy import optimize

# Set precision for calculations
getcontext().prec = 28

class StableSwapSimulator:
    def __init__(self, 
                 initial_balances: List[float], 
                 amplification_parameter: int = 100):
        """
        Initialize the StableSwap simulator
        
        Args:
            initial_balances: List of initial token balances [x, y]
            amplification_parameter: Amplification parameter (A)
        """
        self.balances = [Decimal(str(b)) for b in initial_balances]
        self.amp = Decimal(str(amplification_parameter))
        self.n = len(initial_balances)  # Number of tokens
        self.swap_history = []
        self.price_history = []
        
        # Check that we have exactly 2 tokens to simplify
        if self.n != 2:
            raise ValueError("This simulator only supports 2 tokens for now")
        
        # Calculate initial invariant D
        self.invariant = self._compute_invariant()
            
        # Calculate initial spot price
        self.update_spot_price()
        
        print(f"Pool initialized with:")
        print(f"  - Token X: {self.balances[0]}")
        print(f"  - Token Y: {self.balances[1]}")
        print(f"  - Amplification (A): {self.amp}")
        print(f"  - Invariant (D): {self.invariant}")
        print(f"  - Spot Price (Y/X): {self.spot_price}")
    
    def _invariant_function(self, d, balances):
        """
        Function to calculate f(D) = 0 in Newton's method for StableSwap
        with 2 tokens according to formula: 4A(x+y) + D = 4AD + D³/(4xy)
        
        Args:
            d: Current value of D
            balances: List of balances [x, y]
            
        Returns:
            The value of the invariant function (should be zero at equilibrium)
        """
        # For 2 tokens only
        if len(balances) != 2:
            raise ValueError("This formula only works for 2 tokens")
            
        x, y = float(balances[0]), float(balances[1])
        A = float(self.amp)
        
        # StableSwap formula for 2 tokens
        # 4A(x+y) + D = 4AD + D³/(4xy)
        # Rearranged: 4A(x+y) - 4AD + D - D³/(4xy) = 0
        
        left_side = 4 * A * (x + y) + d
        right_side = 4 * A * d + (d**3) / (4 * x * y)
        
        return left_side - right_side
    
    def _compute_invariant(self) -> Decimal:
        """
        Calculate invariant D using scipy.optimize
        
        Returns:
            The invariant D
        """
        sum_x = sum(self.balances)
        if sum_x == 0:
            return Decimal('0')
        
        # Use Newton's method via scipy.optimize
        result = optimize.newton(
            lambda d: self._invariant_function(d, self.balances),
            float(sum_x),  # Initial estimate for D
            tol=1e-10,
            maxiter=100
        )
        
        return Decimal(str(result))


    def update_spot_price(self):
        """
        Update spot price using total differential
        for StableSwap formula: 4A(x+y) + D = 4AD + D³/(4xy)
        """
        x, y = self.balances[0], self.balances[1]
        x_float, y_float = float(x), float(y)
        d = float(self.invariant)
        A = float(self.amp)
        
        # Calculate partial derivatives for formula 4A(x+y) + D = 4AD + D³/(4xy)
        # ∂f/∂x = 4A - D³/(4x²y)
        # ∂f/∂y = 4A - D³/(4xy²)
        
        df_dx = 4 * A - (d**3) / (4 * (x_float**2) * y_float)
        df_dy = 4 * A - (d**3) / (4 * x_float * (y_float**2))
        
        # Spot price Y/X = -dx/dy = df_dy / df_dx
        self.spot_price = df_dy / df_dx
        
        # Log total differential details
        print("\nSpot price calculation by total differential:")
        print(f"  df/dx = {df_dx}")
        print(f"  df/dy = {df_dy}")
        print(f"  Spot Price (Y/X) = -dx/dy = df_dy / df_dx = {self.spot_price}")
        
        # Add to history
        self.price_history.append((float(x), float(y), float(self.spot_price)))
    
    def solve_for_balance(self, known_balance, balance_index, target_invariant):
        """
        Solve to find the balance that maintains the invariant
        
        Args:
            known_balance: The known balance
            balance_index: Index of known balance (0 for x, 1 for y)
            target_invariant: Target invariant
            
        Returns:
            The calculated balance to maintain the invariant
        """
        # Create function that calculates invariant with variable balance
        def invariant_error(balance):
            balances = [0, 0]
            balances[balance_index] = known_balance
            balances[1 - balance_index] = Decimal(str(balance))
            
            # Calculate invariant with these hypothetical balances
            try:
                invariant_val = self._invariant_function(float(target_invariant), balances)
                return invariant_val
            except:
                return 1e10  # High value in case of error
        
        # Estimate value of other balance
        other_balance = float(self.balances[1 - balance_index])
        
        # Use scipy.optimize to find balance that gives invariant_error = 0
        result = optimize.newton(
            invariant_error,
            other_balance,  # Initial estimate
            tol=1e-10,
            maxiter=100
        )
        
        return Decimal(str(result))
    
    def get_dy_given_dx(self, dx: Decimal) -> Decimal:
        """
        Calculate how much token Y is obtained by swapping dx of token X
        
        Args:
            dx: Amount of token X to swap
            
        Returns:
            dy: Amount of token Y received
        """
        x, y = self.balances[0], self.balances[1]
        
        # Calculate new x
        x_new = x + dx
        
        # Find y_new that maintains invariant
        y_new = self.solve_for_balance(x_new, 0, self.invariant)
        
        # Amount received is difference between old y and new y
        return y - y_new
    
    def get_dx_given_dy(self, dy: Decimal) -> Decimal:
        """
        Calculate how much token X is obtained by swapping dy of token Y
        
        Args:
            dy: Amount of token Y to swap
            
        Returns:
            dx: Amount of token X received
        """
        x, y = self.balances[0], self.balances[1]
        
        # Calculate new y
        y_new = y + dy
        
        # Find x_new that maintains invariant
        x_new = self.solve_for_balance(y_new, 1, self.invariant)
        
        # Amount received is difference between old x and new x
        return x - x_new
    
    def swap_x_for_y(self, dx: float) -> float:
        """
        Swap dx of token X for token Y
        
        Args:
            dx: Amount of token X to swap
            
        Returns:
            dy: Amount of token Y received
        """
        dx_decimal = Decimal(str(dx))
        dy_decimal = self.get_dy_given_dx(dx_decimal)
        
        # Update balances
        self.balances[0] += dx_decimal
        self.balances[1] -= dy_decimal
        
        # Check that invariant is preserved (within epsilon)
        new_invariant = self._compute_invariant()
        invariant_diff = abs(new_invariant - self.invariant)
        
        print(f"\nSwap: {dx} X → {float(dy_decimal)} Y")
        print(f"  - New balances: X={float(self.balances[0])}, Y={float(self.balances[1])}")
        print(f"  - Invariant difference: {float(invariant_diff)}")
        
        # Update invariant and spot price
        self.invariant = new_invariant
        self.update_spot_price()
        
        # Record this swap in history
        self.swap_history.append(('X->Y', float(dx), float(dy_decimal)))
        
        print("Got ::", dy_decimal)
        print("Price ::", dy_decimal/dx_decimal)

        return float(dy_decimal)
    
    def swap_y_for_x(self, dy: float) -> float:
        """
        Swap dy of token Y for token X
        
        Args:
            dy: Amount of token Y to swap
            
        Returns:
            dx: Amount of token X received
        """
        dy_decimal = Decimal(str(dy))
        dx_decimal = self.get_dx_given_dy(dy_decimal)
        
        # Update balances
        self.balances[1] += dy_decimal
        self.balances[0] -= dx_decimal
        
        # Check that invariant is preserved (within epsilon)
        new_invariant = self._compute_invariant()
        invariant_diff = abs(new_invariant - self.invariant)
        
        print(f"\nSwap: {dy} Y → {float(dx_decimal)} X")
        print(f"  - New balances: X={float(self.balances[0])}, Y={float(self.balances[1])}")
        print(f"  - Invariant difference: {float(invariant_diff)}")
        
        # Update invariant and spot price
        self.invariant = new_invariant
        self.update_spot_price()
        
        # Record this swap in history
        self.swap_history.append(('Y->X', float(dy), float(dx_decimal)))
        
        print("Got ::", dx_decimal)
        print("Price ::", dy_decimal/dx_decimal)

        return float(dx_decimal)
    
    def plot_swap_history(self):
        """
        Visualize swap history and spot price evolution
        """
        if not self.price_history:
            print("No history to display")
            return
        
        fig, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=(18, 6))
        
        # Extract data
        x_values = [x for x, _, _ in self.price_history]
        y_values = [y for _, y, _ in self.price_history]
        prices = [p for _, _, p in self.price_history]
        
        # Plot balances
        ax1.plot(x_values, y_values, 'o-', label='Balance trajectory')
        
        # Plot theoretical invariant curve
        if len(x_values) > 0:
            x_range = np.linspace(min(x_values) * 0.8, max(x_values) * 1.2, 100)
            y_ideal = []
            
            # Calculate y balances that maintain invariant
            for x_val in x_range:
                try:
                    y_val = float(self.solve_for_balance(Decimal(str(x_val)), 0, self.invariant))
                    y_ideal.append(y_val)
                except:
                    # In case of error, interpolate between neighboring points
                    y_ideal.append(np.nan)
            
            ax1.plot(x_range, y_ideal, 'r--', label='Invariant curve')
        
        ax1.set_xlabel('X Balance')
        ax1.set_ylabel('Y Balance')
        ax1.set_title('Balance Evolution')
        ax1.grid(True)
        ax1.legend()
        
        # Plot spot price evolution
        indices = list(range(len(prices)))
        ax2.plot(indices, prices, 'o-', label='Spot Price (Y/X)')
        
        # Mark swaps
        for i, (swap_type, amount_in, amount_out) in enumerate(self.swap_history):
            if i < len(prices) - 1:  # Avoid index out of range
                if swap_type == 'X->Y':
                    ax2.annotate(f'+{amount_in}X', 
                                (i+1, prices[i+1]), 
                                textcoords="offset points", 
                                xytext=(0,10), 
                                ha='center')
                else:
                    ax2.annotate(f'+{amount_in}Y', 
                                (i+1, prices[i+1]), 
                                textcoords="offset points", 
                                xytext=(0,10), 
                                ha='center')
        
        ax2.set_xlabel('Swap Number')
        ax2.set_ylabel('Spot Price (Y/X)')
        ax2.set_title('Spot Price Evolution')
        ax2.grid(True)
        
        # Plot spot price vs relative concentration (X/(X+Y))
        concentration = [x/(x+y) for x, y, _ in self.price_history]
        ax3.plot(concentration, prices, 'o-', label='Spot Price vs Concentration')
        ax3.set_xlabel('Concentration X/(X+Y)')
        ax3.set_ylabel('Spot Price (Y/X)')
        ax3.set_title('Price vs Concentration')
        ax3.grid(True)
        
        plt.tight_layout()
        plt.show()
        
        # Display additional graph for spot price derivation
        if len(self.price_history) > 0:
            fig, ax = plt.subplots(figsize=(10, 6))
            
            # Extract data from last state
            x, y = self.balances[0], self.balances[1]
            
            # Calculate values for different A hypotheses
            a_values = [10, 50, 100, 200, 500, 1000]
            
            # Graph parameters
            ratio_range = np.linspace(0.5, 2.0, 100)
            
            for a_val in a_values:
                spot_prices = []
                
                for ratio in ratio_range:
                    # Calculate hypothetical balances
                    x_hyp = float(x) * ratio
                    y_hyp = float(y) / ratio
                    
                    # Amplification
                    amp_hyp = a_val
                    
                    # Calculate D for these balances and amplification
                    def calc_invariant(balances, amp):
                        sum_x = sum(balances)
                        n = len(balances)
                        amp_times_total = amp * n
                        
                        # Use Newton's method via scipy.optimize
                        def inv_func(d):
                            d_p = d
                            for balance in balances:
                                d_p = d_p * d / (balance * n)
                            
                            return (
                                float(amp_times_total) * float(sum_x) -
                                float(amp_times_total) * float(d) +
                                float(d) -
                                float(d) * d_p
                            )
                        
                        result = optimize.newton(
                            inv_func,
                            float(sum_x),
                            tol=1e-10,
                            maxiter=100
                        )
                        
                        return result
                    
                    try:
                        # Calculate spot price for these parameters
                        balances_hyp = [x_hyp, y_hyp]
                        d_hyp = calc_invariant(balances_hyp, amp_hyp)
                        
                        # Calculate a and b
                        a = (amp_hyp * 2)
                        b = d_hyp * a - d_hyp
                        
                        # Partial derivatives
                        df_dx = (2 * a * x_hyp * y_hyp) + (a * x_hyp * x_hyp) + (b * x_hyp)
                        df_dy = (2 * a * x_hyp * y_hyp) + (a * y_hyp * y_hyp) + (b * y_hyp)
                        
                        # Spot price
                        spot_price = df_dy / df_dx
                        spot_prices.append(spot_price)
                    except:
                        spot_prices.append(np.nan)
                
                ax.plot(ratio_range, spot_prices, label=f'A = {a_val}')
            
            # Add references
            ax.plot(ratio_range, [1/r for r in ratio_range], '--', label='Constant Product (x*y=k)')
            ax.axhline(y=1, color='r', linestyle=':', label='Constant Sum (x+y=k)')
            
            ax.set_xlabel('Balance ratio (X/X_initial)')
            ax.set_ylabel('Spot Price (Y/X)')
            ax.set_title('Impact of amplification on spot price')
            ax.grid(True)
            ax.legend()
            
            plt.tight_layout()
            plt.show()


def interactive_simulator():
    """
    Interactive interface for StableSwap simulator
    """
    print("=== StableSwap Simulator ===")
    
    # Ask for initial parameters
    try:
        x_balance = float(input("Initial balance of token X: "))
        y_balance = float(input("Initial balance of token Y: "))
        amp = int(input("Amplification parameter (A): "))
        
        # Initialize simulator
        simulator = StableSwapSimulator([x_balance, y_balance], amp)
        
        while True:
            print("\n=== Menu ===")
            print("1. Swap X for Y")
            print("2. Swap Y for X")
            print("3. Show swap history")
            print("4. Quit")
            
            choice = input("Choose an option (1-4): ")
            
            if choice == '1':
                amount = float(input("Amount of X to swap: "))
                simulator.swap_x_for_y(amount)
            elif choice == '2':
                amount = float(input("Amount of Y to swap: "))
                simulator.swap_y_for_x(amount)
            elif choice == '3':
                simulator.plot_swap_history()
            elif choice == '4':
                print("Thanks for using the simulator!")
                break
            else:
                print("Invalid option. Please try again.")
    
    except ValueError as e:
        print(f"Error: {e}")
        print("Please enter valid numeric values.")
    except Exception as e:
        print(f"An error occurred: {e}")


# Run interactive simulator
if __name__ == "__main__":
    interactive_simulator()