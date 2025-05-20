# MLIP Active Learning Workflow for DBBA on Pd Surfaces

This repository contains a complete workflow for performing active learning-based training and evaluation of machine-learned interatomic potentials (MLIPs), specifically applied to simulations of DBBA on Pd surfaces. The scripts support selecting training configurations based on force uncertainty, preprocessing and splitting trajectories, and analyzing RDFs and model performance across iterations.

---

## 📁 Repository Structure

| File / Script                                                    | Purpose                                                                                                                               |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `ml_config_selection.ipynb`                                      | Jupyter notebook for selecting configurations from MLIP trajectories using uncertainty analysis and configurable selection intervals  |
| `split_xyz.sh`                                                   | Splits large `.xyz` trajectories into per-frame subfolders (`0000/`, `0001/`, etc.) and optionally copies an input template into each |
| `batches.sh`                                                     | Submits DFT calculations in batches of 25 per job — **specific to LUMI** (user must adapt submission directives)                      |
| `combined_processing.sh`                                         | Wrapper script that runs several preprocessing steps on raw data (see inline comments for details)                                    |
| `generate_rdf.py`                                                | Computes radial distribution functions from simulation trajectories                                                                   |
| `instructions_LUMI_deepmd-lammps-plumed-tensorflow_complete.txt` | Environment setup instructions for LUMI cluster                                                                                       |

---

## 🔁 Workflow Overview

1. **Run MLIP-MD trajectories** (e.g., via DeePMD + LAMMPS)
2. **Use `ml_config_selection.ipynb`** to:

   * Load force-uncertainty data from MLIP-MD
   * Define system paths and selection intervals
   * Select configurations with low force std. dev. for DFT refinement
3. **Use `split_xyz.sh`** to:

   * Split trajectory files into per-frame folders
   * Optionally add `sp.inp` input file to each
4. **Submit DFT jobs via `batches.sh`** (adapt to your cluster!)
5. **Process results with `combined_processing.sh`**:

   * Generates typemaps, organizes raw results, converts to final datasets
6. **Compare RDFs and performance** with `generate_rdf.py` or other analysis scripts

---

## ⚙️ Environment & Dependencies

Use the provided LUMI-specific environment setup instructions:

```
instructions_LUMI_deepmd-lammps-plumed-tensorflow_complete.txt
```

Or install manually:

* Python 3.8+
* NumPy, Matplotlib
* DeePMD-kit
* TensorFlow 2.x
* LAMMPS with DeePMD plugin (for MD generation)

---

## 📓 Usage Notes

### `ml_config_selection.ipynb`

* Modify the system path dictionary (e.g. `{ "S1": ".thesis_data/4_dbba/7_mlip/a1" }`)
* Choose **one** system for interval analysis and adjust the interval selection block as directed in the comments

### `split_xyz.sh`

* Usage: `./split_xyz.sh traj.xyz`
* Assumes trajectory is in standard `.xyz` format with fixed number of atoms

### `batches.sh`

* Detects `0000`, `0001`, ... folders in the current directory
* Splits into groups of 25 jobs and submits batch jobs to the **LUMI** cluster
* You must adapt the `sbatch` template to your own HPC scheduler

### `combined_processing.sh`

* Usage: `./combined_processing.sh file.xyz [nline_per_set]`
* Automatically determines number of atoms from the `.xyz` file
* Runs three internal scripts: typemap creation, raw parsing, and final set conversion

### `generate_rdf.py`

* Usage example: `python generate_rdf.py --input traj.xyz --pair Br Pd --bins 200`
* Can be adapted to compare RDFs across DFT and MLIP trajectories

---

## 📊 Outputs

Example figures that can be reproduced using these scripts (if data are available):

* Force std. dev. histograms (before and after retraining)
* Residual force histograms (F<sub>DFT</sub> − F<sub>NN</sub>)
* Radial distribution functions (Br–Pd, C–C, etc.)

---

## 📄 License

This repository is licensed under the **MIT License**.

---

## 📚 How to Cite This Workflow

If you use this workflow or any part of the codebase, please cite:

> *Amador, R. and Brovelli, S. (2025). Active learning workflow for machine-learned interatomic potentials of DBBA on Pd surfaces. GitHub Repository.*

---

## 📬 Contact

For questions or feedback, please contact:
**Raymond Amador** — [GitHub Profile](https://github.com/ramador09/)
