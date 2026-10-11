"""Run the whole pipeline end to end: land raw files in GCS -> bronze -> silver (+ DQ tests) -> gold (+ tests).

Usage:  python src/run_pipeline.py
"""
import load_bronze
import run_gold
import run_silver


def main():
    print("=== 1/3  Landing + bronze")
    load_bronze.main()
    print("\n=== 2/3  Silver + data-quality tests")
    run_silver.main()
    print("\n=== 3/3  Gold + data-quality tests")
    run_gold.main()


if __name__ == "__main__":
    main()
