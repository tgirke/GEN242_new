##########################################################################
## This file contains the functions developed for the challenge project ##
##########################################################################
## The default function included here is from the programming 
## exercise here: https://bit.ly/3fPtiOY

myMAcomp <- function(myMA=myMA, group=c(1,1,1,2,2,2,3,3,4,4), myfct=mean) {
	myList <- tapply(colnames(myMA), group, list)
	names(myList) <- sapply(myList, paste, collapse="_")
	myMAmean <- sapply(myList, function(x) apply(myMA[, x, drop=FALSE], 1, myfct))
	return(myMAmean)
}
## Usage:
# myMA <- matrix(rnorm(100000), 10000, 10, dimnames=list(1:10000, paste("C", 1:10, sep="")))
# myMAcomp(myMA=myMA, group=c(1,1,1,2,2,2,3,3,4,4), myfct=mean)[1:2,] 

