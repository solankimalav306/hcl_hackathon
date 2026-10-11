"""Run the whole pipeline end to end: land raw files in GCS -> bronze -> silver (+ DQ tests).

Usage:  python src/run_pipeline.py
"""
import load_bronze
import run_silver


def main():
    print("=== 1/2  Landing + bronze")
    load_bronze.main()
    print("\n=== 2/2  Silver + data-quality tests")
    run_silver.main()


if __name__ == "__main__":
    main()
