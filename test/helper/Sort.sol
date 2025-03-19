// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/// Main import
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Sort {
    constructor() {}

    // --- simple sort IERC20 ---

    function quickSort(uint256[] memory arr, int256 left, int256 right) internal pure {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) {
            quickSort(arr, left, j);
        }
        if (i < right) {
            quickSort(arr, i, right);
        }
    }

    function sortUint(uint256[] memory data) internal pure returns (uint256[] memory) {
        quickSort(data, int256(0), int256(data.length - 1));
        return data;
    }

    function sort(IERC20[] memory data) public pure returns (IERC20[] memory retIERC20) {
        uint256[] memory arr = new uint256[](data.length);
        retIERC20 = new IERC20[](data.length);

        for (uint256 i = 0; i < data.length; i++) {
            arr[i] = uint256(uint160(address(data[i])));
        }

        arr = sortUint(arr);

        for (uint256 i = 0; i < data.length; i++) {
            retIERC20[i] = IERC20(address(uint160((arr[i]))));
        }
    }

    // --- double sort IERC20 and amount ---

    function quickSort(uint256[] memory arr, uint256[] memory arr2, int256 left, int256 right)
        internal
        pure
    {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                (arr2[uint256(i)], arr2[uint256(j)]) = (arr2[uint256(j)], arr2[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) {
            quickSort(arr, arr2, left, j);
        }
        if (i < right) {
            quickSort(arr, arr2, i, right);
        }
    }

    function sortUint(uint256[] memory data, uint256[] memory arr2)
        internal
        pure
        returns (uint256[] memory, uint256[] memory)
    {
        quickSort(data, arr2, int256(0), int256(data.length - 1));
        return (data, arr2);
    }

    function sort(IERC20[] memory data, uint256[] memory amounts)
        internal
        pure
        returns (IERC20[] memory retIERC20, uint256[] memory retAmounts)
    {
        uint256[] memory arr = new uint256[](data.length);
        retIERC20 = new IERC20[](data.length);
        retAmounts = new uint256[](data.length);

        for (uint256 i = 0; i < data.length; i++) {
            arr[i] = uint256(uint160(address(data[i])));
        }

        (arr, retAmounts) = sortUint(arr, amounts);

        for (uint256 i = 0; i < data.length; i++) {
            retIERC20[i] = IERC20(address(uint160((arr[i]))));
        }
    }
}
