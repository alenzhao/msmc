/* Copyright (c) 2012,2013 Genome Research Ltd.
 *
 * Author: Stephan Schiffels <stephan.schiffels@sanger.ac.uk>
 *
 * This file is part of msmc.
 * msmc is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation; either version 3 of the License, or (at your option) any later
 * version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 */
 
import std.stdio;
import std.math;
import std.string;
import std.conv;
import std.getopt;
import std.parallelism;
import std.algorithm;
import std.array;
import std.json;
import std.file;
import std.typecons;
import std.exception;
import std.c.stdlib;
import core.memory;
import model.msmc_hmm;
import model.msmc_model;
import model.triple_index_marginal;
import model.emission_rate;
import model.transition_rate;
import model.time_intervals;
import model.triple_index_marginal;
import model.coalescence_rate;
import model.rate_integrator;
import model.propagation_core_fastImpl;
import model.data;
import expectation_step;

void estimateTotalBranchlengths(SegSite_t[] inputData, MSMCmodel params, size_t internalNrSegments) {

  auto propagationCore = buildPropagationCore(params, internalNrSegments);
  auto msmc_hmm = buildHMM(inputData, propagationCore);
    
  msmc_hmm.runForward();
  
  auto forwardState = propagationCore.newForwardState();
  auto backwardState = propagationCore.newBackwardState();

  foreach_reverse(dataIndex; 0 .. inputData.length) {
    msmc_hmm.getForwardState(forwardState, inputData[dataIndex].pos);
    msmc_hmm.getBackwardState(backwardState, inputData[dataIndex].pos);
    double ttot = 2.0 * propagationCore.msmc.timeIntervals.meanTimeWithLambda(0, 1.0);
    auto max = forwardState.vec[0] * backwardState.vec[0];
    foreach(i; 0 .. params.nrTimeIntervals) {
      auto p = forwardState.vec[i] * backwardState.vec[i];
      if(p > max) {
        max = p;
        // we need the total branch length, so twice the tMRCA with two haplotypes
        ttot = 2.0 * propagationCore.msmc.timeIntervals.meanTimeWithLambda(i, 1.0);
      }
    }
    inputData[dataIndex].i_Ttot = params.tTotIntervals.findIntervalForTime(ttot);
  }
}
  
private PropagationCoreFast buildPropagationCore(MSMCmodel params, size_t internalNrSegments) {
  auto lambdaVec = new double[internalNrSegments];
  lambdaVec[] = 1.0;
  // the factor 2 is just part of the formula for the mean total branch length.
  auto expectedTtot = 2.0 * TimeIntervals.computeWattersonFactor(params.nrHaplotypes);
  // the next factor 2 fakes a two haplotype system with the same total branch length (every branch gets half)
  auto boundaries = TimeIntervals.getQuantileBoundaries(internalNrSegments, expectedTtot / 2.0);
  auto model = new MSMCmodel(params.mutationRate, params.recombinationRate, [0UL, 0], lambdaVec, boundaries[0 .. $ - 1], 1);

  auto propagationCore = new PropagationCoreFast(model, 1000);
  return propagationCore;
}
  
private MSMC_hmm buildHMM(SegSite_t[] inputData, PropagationCoreFast propagationCore) {
  SegSite_t[] dummyInputData;
  foreach(s; inputData) {
    auto dummySite = s.dup;
    if(s.obs.length > 1 || s.obs[0] > 1)
      dummySite.obs = [2];
    dummyInputData ~= dummySite;
  }
    
  return new MSMC_hmm(propagationCore, dummyInputData);
}
