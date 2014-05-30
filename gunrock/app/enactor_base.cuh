// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * enactor_base.cuh
 *
 * @brief Base Graph Problem Enactor
 */

#pragma once

#include <gunrock/util/cuda_properties.cuh>
#include <gunrock/util/cta_work_progress.cuh>
#include <gunrock/util/error_utils.cuh>
#include <gunrock/util/test_utils.cuh>

#include <gunrock/app/problem_base.cuh>

namespace gunrock {
namespace app {

/**
 * @brief Base class for graph problem enactors.
 */
class EnactorBase
{
protected:  

    //Device properties
    util::CudaProperties cuda_props;
    
    // Queue size counters and accompanying functionality
    // Move to indiviual Enactor classes to support multi GPU
    //util::CtaWorkProgressLifetime work_progress;

    FrontierType frontier_type;

public:

    // if DEBUG is set, print details to stdout
    bool DEBUG;

    FrontierType GetFrontierType() { return frontier_type;}

protected:  

    /**
     * @brief Constructor
     *
     * @param[in] frontier_type The frontier type (i.e., edge/vertex/mixed)
     * @param[in] DEBUG If set, will collect kernel running stats and display the running info.
     */
    EnactorBase(FrontierType frontier_type, bool DEBUG) :
        frontier_type(frontier_type),
        DEBUG(DEBUG)
    {
        // Setup work progress (only needs doing once since we maintain
        // it in our kernel code)
        //work_progress.Setup();
    }

    /**
     * @brief Utility function for getting the max grid size.
     *
     * @param[in] cta_occupancy CTA occupancy for current architecture
     * @param[in] max_grid_size Preset max grid size. If less or equal to 0, fully populate all SMs
     *
     * \return The maximum number of threadblocks this enactor class can launch.
     */
    int MaxGridSize(int cta_occupancy, int max_grid_size = 0)
    {
        if (max_grid_size <= 0) {
            max_grid_size = this->cuda_props.device_props.multiProcessorCount * cta_occupancy;
        }

        return max_grid_size;
    }

};


} // namespace app
} // namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
